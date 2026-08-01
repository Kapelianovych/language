:- module(types, [
  empty_context/1,
  fresh_unification_variable/4,
  fresh_bound_id/3,
  fresh_named_bound_id/4,
  fresh_named_bound_id/5,
  record_variable_bound/5,
  variable_bound_info/4,
  any_bound/3,
  resolve_head/3,
  fully_resolve/3,
  unify/4,
  subsume/5,
  skolemize_forall/6,
  instantiate_forall/5,
  instantiate_forall_positional/6,
  generalize/5,
  substitute_skolems/3,
  instantiate/5,
  instantiate_positional/6,
  monomorphic_type_scheme/2,
  collect_quantified_ids/2,
  quantified_name_table/3,
  scheme_free_unification_variables/2,
  context_substitution/2
]).

/*  types.pl  --  Type language + level-based algorithmic context.

    Implements the level-based algorithmic type system of Fan, Xu & Xie,
    "Practical Type Inference with Levels" (PLDI'25), with let-generalisation
    as in Heeren, Hage & Swierstra (UU-CS-2002-031), extended with
    Remy/Wand-style ROW POLYMORPHISM for records (records).

    --------------------------------------------------------------------
    THE TYPE LANGUAGE
    --------------------------------------------------------------------
    A monotype is one of:

        number / boolean / string       base types
        readonly / mutable              base types, used only in the
                                        mutability slot of a record field
                                        (so mutability unifies like any type)
        unification_variable(Id)        an as-yet-unknown type/row; level and
                                        solution live in the context
        function_type(Params, Ret)      an n-ary function `(t1 .. tn) -> r`
        type_constructor(Name, Args)    a NOMINAL named type (see below)
        record_type(Fields, Tail)        a RECORD; see below
        forall_type(BoundIds, Body)     a RANK-N polytype `forall a.. . Body`;
                                        the bound variables appear in Body as
                                        `quantified_variable(Id)`.  Unlike a
                                        `type_scheme`, a `forall_type` is a
                                        first-class monotype, so it may NEST
                                        (a function parameter / field whose
                                        type is itself polymorphic).
        type_lambda(BoundIds, Body)     a TYPE-LEVEL FUNCTION produced by a
                                        partial type application / SECTION
                                        (`Either<_ string>`, `Either<number>`).
                                        Its kind is its arity; applying it to
                                        that many arguments BETA-REDUCES (the
                                        bound ids, appearing in Body as
                                        `quantified_variable(Id)`, are replaced
                                        by the arguments).
        skolem(Id, Level, Name)         a rigid, opaque constant standing for a
                                        universally-quantified variable while
                                        CHECKING a value against a polytype.
                                        Its `Level` powers the escape check:
                                        a unification variable at a shallower
                                        level may not capture it (that would
                                        let the skolem leak its scope).  `Name`
                                        is the type parameter's SOURCE NAME
                                        (or `anonymous`), carried only so
                                        error messages can say `A` instead of
                                        an opaque id; identity is the Id.

    --------------------------------------------------------------------
    RANK-N POLYMORPHISM (predicative, bidirectional)
    --------------------------------------------------------------------
    `forall_type` is introduced by an explicit annotation and eliminated two
    ways: INSTANTIATED (its `forall` opened to fresh unification variables)
    when a polymorphic value is used at a specific type, and SKOLEMISED (its
    `forall` opened to fresh rigid skolems) when a value is CHECKED to have a
    polymorphic type.  `subsume/5` is the directed "is at least as polymorphic
    as" check (Peyton Jones et al., JFP'07; Dunfield & Krishnaswami, ICFP'13):
    it instantiates the actual type, skolemises the expected type, and is
    contravariant in function arguments.  Predicativity is enforced upstream
    (a polytype may not be a type ARGUMENT), so unification variables only ever
    stand for monotypes.

    TUPLES AS ROWS.  A `record_type(Fields, Tail)` is a record:

        Fields  a list of  record_field(Mutability, Key, Type)
                  Key is  index(N)   for a positional member, or
                          label(Name) for a labeled member.
        Tail    either `closed` (these are exactly the fields) or a
                unification variable -- a ROW VARIABLE standing for "any
                further fields".  Solving a row variable binds it to another
                `record_type(MoreFields, FurtherTail)`, so an open record is a
                chain that `flatten_record/4` collapses.

    A record LITERAL is closed.  A member access only requires "a record with
    at least this field" -- an open tail -- which is what makes functions
    like `(p) p.x` row-polymorphic: the row variable is generalised.

    NOMINAL vs STRUCTURAL.  `function_type` and `record_type` unify
    structurally.  `type_constructor` unifies NOMINALLY (only equal names).

    A *type scheme* is `type_scheme(QuantifiedIds, Body)`; generalised
    variables (type OR row) appear as `quantified_variable(Id)` in `Body`.

    --------------------------------------------------------------------
    THE ALGORITHMIC CONTEXT (Fig. 4 of the levels paper)
    --------------------------------------------------------------------
        context(NextVariableId, Store)

    `Store` maps a variable id to `unsolved(Level)` or `solved(Type)`.
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).

% empty_context(-Context).
empty_context(context(0, Store)) :-
  empty_assoc(Store).

% fresh_unification_variable(+ContextIn, +Level, -Variable, -ContextOut).
fresh_unification_variable(context(Id, Store), Level, unification_variable(Id),
                           context(NextId, Store1)) :-
  NextId is Id + 1,
  put_assoc(Id, Store, unsolved(Level), Store1).

% fresh_bound_id(+ContextIn, -Id, -ContextOut).
%
% Allocate a fresh, globally-unique id WITHOUT minting a unification variable
% for it -- used for the bound variables of a `forall_type` and for skolem
% constants, neither of which lives in the solution store.
fresh_bound_id(context(Id, Store), Id, context(NextId, Store)) :-
  NextId is Id + 1.

% fresh_named_bound_id(+ContextIn, +Name, -Id, -ContextOut).
%
% Like fresh_bound_id, but records the bound variable's source name in the
% store (as `bound_name(Name, no_bound)`), so a later skolemisation of the
% enclosing `forall_type` can carry the name into error messages (see
% fresh_skolem_mapping). Kept for callers that have no bound expression to
% preserve; `fresh_named_bound_id/5` is the general form.
fresh_named_bound_id(ContextIn, Name, Id, ContextOut) :-
  fresh_named_bound_id(ContextIn, Name, no_bound, Id, ContextOut).

% fresh_named_bound_id(+ContextIn, +Name, +Bound, -Id, -ContextOut).
%
% `Bound` is the parameter's declared bound, ALREADY CONVERTED to a type by
% the caller (`no_bound` or a fully-formed monotype).  Used for an id that is
% NOT also a live unification variable (a standalone `<A: Bound>` quantified
% type expression, or a definition's forward-reference scheme; see
% `bind_quantifier_parameters/6` in type_environment.pl) -- such an id never
% gets an `unsolved`/`solved` store entry, so its metadata can live directly
% under its own key.  `record_variable_bound/5` is the sibling for an id that
% DOES already own that key.
fresh_named_bound_id(context(Id, Store), Name, Bound, Id, context(NextId, Store1)) :-
  NextId is Id + 1,
  put_assoc(Id, Store, bound_name(Name, Bound), Store1).

% record_variable_bound(+ContextIn, +Id, +Name, +Bound, -ContextOut).
%
% Attach a declared NAME and BOUND to an id that is ALREADY a live unification
% variable (minted by `fresh_unification_variable/4`, so it owns an
% `unsolved(Level)`/`solved(Type)` entry under the plain `Id` key) -- stored
% under the DISTINCT key `bound_of(Id)` so it cannot clobber that tracking.
%
% This is how a function/module's OWN explicit generic (`<A: Bound>`) keeps
% its identity: `bind_type_parameters_rigid` checks the body against a rigid
% SKOLEM (which carries `Name` directly in its own term), then swaps that
% skolem back to this flexible id before generalising -- so the skolem's name
% and bound would otherwise vanish the instant it is discarded.  Recording
% them here lets both hover (hover shows `Name`, `Bound` at the definition)
% and enforcement (`any_bound/3`, consulted by `bind_unification_variable/4`
% and the instantiation helpers below) survive past that swap, and further
% survive re-instantiation at every later call site or re-generalisation.
record_variable_bound(context(NextId, Store), Id, Name, Bound, context(NextId, Store1)) :-
  put_assoc(bound_of(Id), Store, Name - Bound, Store1).

% variable_bound_info(+Context, +Id, -Name, -Bound).
%
% Read either storage shape transparently: `Name` is `anonymous` and `Bound`
% is `no_bound` when neither has an entry for `Id` (an ordinary, unbounded,
% unnamed variable).
variable_bound_info(context(_, Store), Id, Name, Bound) :-
  ( get_assoc(bound_of(Id), Store, Name0 - Bound0) -> Name = Name0, Bound = Bound0
  ; get_assoc(Id, Store, bound_name(Name0, Bound0)) -> Name = Name0, Bound = Bound0
  ; Name = anonymous, Bound = no_bound
  ).

% The recorded source name of a bound id, or `anonymous` when it was minted
% nameless (synthetic type-lambda positions, imported schemes).
bound_id_name(Context, Id, Name) :- variable_bound_info(Context, Id, Name, _Bound).

% any_bound(+Context, +Id, -Bound).
%
% Just the bound half of `variable_bound_info/4` -- what `bind_unification_
% variable/4` and the instantiation helpers below consult to decide whether
% a freshly solved/instantiated id has anything to enforce.
any_bound(Context, Id, Bound) :- variable_bound_info(Context, Id, _Name, Bound).

% monomorphic_type_scheme(+Type, -Scheme).
monomorphic_type_scheme(Type, type_scheme([], Type)).

% ---------------------------------------------------------------------------
% Resolution (context application, Fig. 4)
% ---------------------------------------------------------------------------

% resolve_head(+Type, +Context, -Resolved).
%
% Follow solved unification variables one head level deep.
resolve_head(Type, Context, Resolved) :-
  ( Type = unification_variable(Id) ->
      Context = context(_, Store),
      get_assoc(Id, Store, Entry),
      ( Entry = solved(Solution) ->
          resolve_head(Solution, Context, Resolved)
      ; Resolved = Type
      )
  ; Type = type_application(Head, Arguments) ->
      % Normalise a higher-kinded application once its head is known: with a
      % constructor head `F<A>` (F = Option) becomes the nominal `Option<A>`;
      % with a SECTION head (a type_lambda) it BETA-REDUCES.
      resolve_head(Head, Context, ResolvedHead),
      ( ResolvedHead = constructor_ref(Name) ->
          Resolved = type_constructor(Name, Arguments)
      ; ResolvedHead = type_lambda(BoundIds, Body), same_length(BoundIds, Arguments) ->
          zip_mapping(BoundIds, Arguments, Mapping),
          substitute_quantified_variables(Body, Mapping, Reduced),
          resolve_head(Reduced, Context, Resolved)
      ; Resolved = type_application(ResolvedHead, Arguments)
      )
  ; Resolved = Type
  ).

% Pair each bound id with its argument for `substitute_quantified_variables`.
zip_mapping([], [], []).
zip_mapping([Id | Ids], [Argument | Arguments], [Id - Argument | Mapping]) :-
  zip_mapping(Ids, Arguments, Mapping).

% fully_resolve(+Type, +Context, -Resolved).
%
% Deep context application, leaving no solved variables.  Record chains are
% flattened so the result is a single `record_type(AllFields, FinalTail)`.
fully_resolve(Type, Context, Resolved) :-
  resolve_head(Type, Context, Head),
  ( Head = function_type(Parameters, Return) ->
      fully_resolve_list(Parameters, Context, Parameters1),
      fully_resolve(Return, Context, Return1),
      Resolved = function_type(Parameters1, Return1)
  ; Head = record_type(_, _) ->
      flatten_record(Head, Context, Fields, Tail),
      fully_resolve_fields(Fields, Context, Fields1),
      Resolved = record_type(Fields1, Tail)
  ; Head = type_constructor(Name, Arguments) ->
      fully_resolve_list(Arguments, Context, Arguments1),
      Resolved = type_constructor(Name, Arguments1)
  ; Head = type_application(ApplicationHead, Arguments) ->
      % A higher-kinded application.  Once the head is a known constructor it
      % normalises to a plain nominal type; otherwise the head stays a variable.
      fully_resolve(ApplicationHead, Context, ResolvedHead),
      fully_resolve_list(Arguments, Context, Arguments1),
      ( ResolvedHead = constructor_ref(Name) ->
          Resolved = type_constructor(Name, Arguments1)
      ; Resolved = type_application(ResolvedHead, Arguments1)
      )
  ; Head = forall_type(BoundIds, Body) ->
      fully_resolve(Body, Context, Body1),
      Resolved = forall_type(BoundIds, Body1)
  ; Head = type_lambda(BoundIds, Body) ->
      fully_resolve(Body, Context, Body1),
      Resolved = type_lambda(BoundIds, Body1)
  ; Head = intersection_type(Members) ->
      % Exactly like `type_constructor`'s Arguments above -- an intersection
      % has no "tail" or head of its own to resolve, just a flat list of
      % member types, each fully resolved the same way any sub-type would be.
      fully_resolve_list(Members, Context, Members1),
      Resolved = intersection_type(Members1)
  ; Resolved = Head                          % base type, skolem, constructor_ref
  ).

fully_resolve_list([], _, []).
fully_resolve_list([Type | Types], Context, [Resolved | Rest]) :-
  fully_resolve(Type, Context, Resolved),
  fully_resolve_list(Types, Context, Rest).

% Resolve the mutability and type carried by each field, keeping the key.
fully_resolve_fields([], _, []).
fully_resolve_fields([record_field(Mutability, Key, Type) | Fields], Context,
                     [record_field(Mutability1, Key, Type1) | Rest]) :-
  fully_resolve(Mutability, Context, Mutability1),
  fully_resolve(Type, Context, Type1),
  fully_resolve_fields(Fields, Context, Rest).

% Collapse an open-record chain into its full field list and final tail.
% The tail is resolved to either `closed` or an unsolved unification variable.
flatten_record(record_type(Fields, Tail), Context, AllFields, FinalTail) :-
  resolve_head(Tail, Context, ResolvedTail),
  ( ResolvedTail = record_type(MoreFields, FurtherTail) ->
      flatten_record(record_type(MoreFields, FurtherTail), Context, RestFields, FinalTail),
      append(Fields, RestFields, AllFields)
  ; AllFields = Fields,
    FinalTail = ResolvedTail
  ).

% The monotypes carried by a field (its mutability and its type), used by the
% occurs check and variable collection, which treat both like any subtype.
field_monotypes([], []).
field_monotypes([record_field(Mutability, _, Type) | Fields], [Mutability, Type | Rest]) :-
  field_monotypes(Fields, Rest).

% ---------------------------------------------------------------------------
% Unification with level adjustment (Fig. 6)
% ---------------------------------------------------------------------------

% unify(+Type1, +Type2, +ContextIn, -ContextOut).
unify(Type1, Type2, ContextIn, ContextOut) :-
  resolve_head(Type1, ContextIn, Resolved1),
  resolve_head(Type2, ContextIn, Resolved2),
  unify_resolved(Resolved1, Resolved2, ContextIn, ContextOut).

unify_resolved(unification_variable(Id), unification_variable(Id), Context, Context) :- !.
unify_resolved(unification_variable(Id), Type, ContextIn, ContextOut) :- !,
  bind_unification_variable(Id, Type, ContextIn, ContextOut).
unify_resolved(Type, unification_variable(Id), ContextIn, ContextOut) :- !,
  bind_unification_variable(Id, Type, ContextIn, ContextOut).
unify_resolved(number, number, Context, Context) :- !.
unify_resolved(boolean, boolean, Context, Context) :- !.
unify_resolved(string, string, Context, Context) :- !.
unify_resolved(readonly, readonly, Context, Context) :- !.
unify_resolved(mutable, mutable, Context, Context) :- !.
% A readonly/mutable clash is reported specifically (it is what rejects an
% assignment to a readonly member, and a readonly-vs-mutable annotation).
unify_resolved(readonly, mutable, _, _) :- !,
  throw(analysis_error(mutability_mismatch(readonly, mutable))).
unify_resolved(mutable, readonly, _, _) :- !,
  throw(analysis_error(mutability_mismatch(mutable, readonly))).
unify_resolved(function_type(Params1, Return1), function_type(Params2, Return2),
               ContextIn, ContextOut) :- !,
  ( same_length(Params1, Params2) ->
      unify_list(Params1, Params2, ContextIn, Context1),
      unify(Return1, Return2, Context1, ContextOut)
  ; throw(analysis_error(function_arity_mismatch(Params1, Params2)))
  ).
% STRUCTURAL, row-polymorphic rule for records.
unify_resolved(record_type(Fields1, Tail1), record_type(Fields2, Tail2), ContextIn, ContextOut) :- !,
  flatten_record(record_type(Fields1, Tail1), ContextIn, AllFields1, FinalTail1),
  flatten_record(record_type(Fields2, Tail2), ContextIn, AllFields2, FinalTail2),
  unify_rows(AllFields1, FinalTail1, AllFields2, FinalTail2, ContextIn, ContextOut).
% NOMINAL rule: type constructors unify only when names match.
unify_resolved(type_constructor(Name, Arguments1), type_constructor(Name, Arguments2),
               ContextIn, ContextOut) :- !,
  ( same_length(Arguments1, Arguments2) ->
      unify_list(Arguments1, Arguments2, ContextIn, ContextOut)
  ; throw(analysis_error(type_constructor_arity_mismatch(Name, Arguments1, Arguments2)))
  ).
% HIGHER-KINDED rules.  A `type_application` always has a variable head here
% (a constructor head would have normalised away in resolve_head).  Two
% applications decompose; an application against a nominal type pins its head
% to that constructor (`F<A> ~ Option<n>` gives `F = Option`, `A = n`).
unify_resolved(type_application(Head1, Arguments1), type_application(Head2, Arguments2),
               ContextIn, ContextOut) :- !,
  ( same_length(Arguments1, Arguments2) ->
      unify(Head1, Head2, ContextIn, Context1),
      unify_list(Arguments1, Arguments2, Context1, ContextOut)
  ; throw(analysis_error(higher_kinded_arity_mismatch(Arguments1, Arguments2)))
  ).
unify_resolved(type_application(Head, Arguments1), type_constructor(Name, Arguments2),
               ContextIn, ContextOut) :- !,
  ( same_length(Arguments1, Arguments2) ->
      unify(Head, constructor_ref(Name), ContextIn, Context1),
      unify_list(Arguments1, Arguments2, Context1, ContextOut)
  ; throw(analysis_error(higher_kinded_arity_mismatch(Arguments1, Arguments2)))
  ).
unify_resolved(type_constructor(Name, Arguments1), type_application(Head, Arguments2),
               ContextIn, ContextOut) :- !,
  ( same_length(Arguments1, Arguments2) ->
      unify(constructor_ref(Name), Head, ContextIn, Context1),
      unify_list(Arguments1, Arguments2, Context1, ContextOut)
  ; throw(analysis_error(higher_kinded_arity_mismatch(Arguments1, Arguments2)))
  ).
unify_resolved(constructor_ref(Name), constructor_ref(Name), Context, Context) :- !.
% A skolem is rigid: it unifies only with the very same skolem (the var cases
% above already handle a flexible variable capturing a skolem, subject to the
% level escape check).
unify_resolved(skolem(Id, _, _), skolem(Id, _, _), Context, Context) :- !.
% Two polytypes unify by alpha-equivalence: open both with ONE shared set of
% skolems (positionally) and unify the bodies.  Mismatched arities, or bodies
% that force a shared skolem to differ, fail.
unify_resolved(forall_type(Ids1, Body1), forall_type(Ids2, Body2), ContextIn, ContextOut) :- !,
  ( same_length(Ids1, Ids2) ->
      shared_skolem_mappings(Ids1, Ids2, ContextIn, Mapping1, Mapping2, Context1),
      substitute_quantified_variables(Body1, Mapping1, Body1Skolemized),
      substitute_quantified_variables(Body2, Mapping2, Body2Skolemized),
      unify(Body1Skolemized, Body2Skolemized, Context1, ContextOut)
  ; throw(analysis_error(type_mismatch(forall_type(Ids1, Body1), forall_type(Ids2, Body2))))
  ).
% Two SECTIONS unify by alpha-equivalence, exactly like polytypes: share one
% set of skolems positionally and unify the bodies.
unify_resolved(type_lambda(Ids1, Body1), type_lambda(Ids2, Body2), ContextIn, ContextOut) :- !,
  ( same_length(Ids1, Ids2) ->
      shared_skolem_mappings(Ids1, Ids2, ContextIn, Mapping1, Mapping2, Context1),
      substitute_quantified_variables(Body1, Mapping1, Body1Skolemized),
      substitute_quantified_variables(Body2, Mapping2, Body2Skolemized),
      unify(Body1Skolemized, Body2Skolemized, Context1, ContextOut)
  ; throw(analysis_error(type_mismatch(type_lambda(Ids1, Body1), type_lambda(Ids2, Body2))))
  ).
% INTERSECTION rule: two intersections unify (are the SAME type) when their
% member SETS correspond one-to-one, order-insensitively -- `B + C` and
% `C + D` unify iff `{B, C}` and `{C, D}` can be paired up member-for-member
% (here that would need `B ~ C` or `B ~ D` etc., which likely fails; `B + C`
% and `C + B` trivially succeed, pairing each member with itself under the
% other order).  There is no "one side plain, other side an intersection"
% unify rule: the parser only ever BUILDS an `intersection_type` from 2+
% members (a bare `B` with no `+` is never wrapped), so that mixed shape
% never arises from ordinary source, and `unify` is used for EQUALITY
% checks (two annotations of the same variable, etc.) where "is B alone the
% same type as B + C" should indeed just fall through to the catch-all
% below and be rejected as a mismatch, not specially accepted.
unify_resolved(intersection_type(Members1), intersection_type(Members2), ContextIn, ContextOut) :- !,
  ( same_length(Members1, Members2) ->
      unify_intersection_members(Members1, Members2, ContextIn, ContextOut)
  ; throw(analysis_error(intersection_arity_mismatch(Members1, Members2)))
  ).
unify_resolved(TypeA, TypeB, ContextIn, _) :-
  fully_resolve(TypeA, ContextIn, ResolvedA),
  fully_resolve(TypeB, ContextIn, ResolvedB),
  throw(analysis_error(type_mismatch(ResolvedA, ResolvedB))).

% Match every member of `Members1` against SOME not-yet-claimed member of
% `Members2` that it unifies with -- like `match_fields`'s pairing for row
% unification, but there is no KEY to pair by here (an intersection member
% has no label), so each candidate is tried in turn via ordinary Prolog
% backtracking (`select_unifiable`'s second clause has no cut, so failing
% deeper in the recursion backtracks into an earlier pairing choice).
unify_intersection_members([], [], Context, Context).
unify_intersection_members([Member1 | Rest1], Members2, ContextIn, ContextOut) :-
  select_unifiable(Member1, Members2, Rest2, ContextIn, Context1),
  unify_intersection_members(Rest1, Rest2, Context1, ContextOut).

% Try to unify `Member` against the FIRST candidate; if that THROWS (a real
% mismatch -- see `unify_resolved`'s final clause above, every genuine
% mismatch throws, it never just fails), catch it and treat it as an
% ordinary Prolog failure so backtracking can try the next candidate
% instead -- an uncaught throw would abort the whole search immediately
% rather than let a later candidate succeed.  Each attempt starts from a
% FRESH `ContextIn`, so a failed candidate's partial bindings (from before
% it threw) are simply discarded, never threaded into the next attempt.
% If every candidate has been tried and none unified, THROW rather than let
% this fail silently: `unify_resolved`'s intersection clause above already
% committed with a cut before calling down into this, so an ordinary Prolog
% failure at this point would surface as a bare failure with no diagnostic
% -- exactly what this project's `internal_error` backstop and `errors.pl`
% suite exist to catch (see their own comments: every rejected program must
% throw, never just fail).
select_unifiable(Member, [], _, ContextIn, _ContextOut) :-
  fully_resolve(Member, ContextIn, Resolved),
  throw(analysis_error(no_matching_intersection_member(Resolved))).
select_unifiable(Member, [Candidate | Rest], Rest, ContextIn, ContextOut) :-
  catch(unify(Member, Candidate, ContextIn, ContextOut), analysis_error(_), fail), !.
select_unifiable(Member, [Candidate | Rest], [Candidate | RestOut], ContextIn, ContextOut) :-
  select_unifiable(Member, Rest, RestOut, ContextIn, ContextOut).

% Map two equal-length id lists to a single fresh skolem sequence, one mapping
% per side, so the two bodies are compared under identical rigid constants.
shared_skolem_mappings([], [], Context, [], [], Context).
shared_skolem_mappings([Id1 | Ids1], [Id2 | Ids2], ContextIn,
                       [Id1 - Skolem | Mapping1], [Id2 - Skolem | Mapping2], ContextOut) :-
  fresh_bound_id(ContextIn, SkolemId, Context1),
  ( bound_id_name(ContextIn, Id1, Name), Name \== anonymous -> true
  ; bound_id_name(ContextIn, Id2, Name)
  ),
  Skolem = skolem(SkolemId, 0, Name),
  shared_skolem_mappings(Ids1, Ids2, Context1, Mapping1, Mapping2, ContextOut).

unify_list([], [], Context, Context).
unify_list([A | As], [B | Bs], ContextIn, ContextOut) :-
  unify(A, B, ContextIn, Context1),
  unify_list(As, Bs, Context1, ContextOut).

% ---------------------------------------------------------------------------
% Row unification (Remy's algorithm)
% ---------------------------------------------------------------------------
%
% Unify two flattened records.  Fields present in both are unified (by key,
% so labels are order-insensitive and positional indices line up).  Fields
% present in only one must be absorbed by the OTHER record's tail.
unify_rows(Fields1, Tail1, Fields2, Tail2, ContextIn, ContextOut) :-
  match_fields(Fields1, Fields2, Common, Only1, Only2),
  unify_common_fields(Common, ContextIn, Context1),
  close_rows(Only1, Tail1, Only2, Tail2, Context1, ContextOut).

% Pair up fields by key; `Only1`/`Only2` are the unmatched remainders.
match_fields([], Fields2Remaining, [], [], Fields2Remaining).
match_fields([Field1 | Rest1], Fields2, Common, Only1, Only2) :-
  Field1 = record_field(_, Key, _),
  ( select_field(Key, Fields2, Field2, Fields2Rest) ->
      Common = [Field1 - Field2 | CommonRest],
      match_fields(Rest1, Fields2Rest, CommonRest, Only1, Only2)
  ; Only1 = [Field1 | Only1Rest],
    match_fields(Rest1, Fields2, Common, Only1Rest, Only2)
  ).

select_field(Key, [record_field(M, Key, T) | Rest], record_field(M, Key, T), Rest) :- !.
select_field(Key, [Other | Rest], Found, [Other | RestOut]) :-
  select_field(Key, Rest, Found, RestOut).

unify_common_fields([], Context, Context).
unify_common_fields([record_field(M1, _, T1) - record_field(M2, _, T2) | Rest], ContextIn, ContextOut) :-
  unify(M1, M2, ContextIn, Context1),     % mutability (readonly/mutable/var)
  unify(T1, T2, Context1, Context2),
  unify_common_fields(Rest, Context2, ContextOut).

% Reconcile the leftover fields against the two tails.  `Only2` (fields only
% in record 2) must come from record 1's tail, and vice versa.
close_rows(Only1, Tail1In, Only2, Tail2In, ContextIn, ContextOut) :-
  resolve_head(Tail1In, ContextIn, Tail1),
  resolve_head(Tail2In, ContextIn, Tail2),
  ( Tail1 == closed, Tail2 == closed ->
      require_no_extra_fields(Only1),
      require_no_extra_fields(Only2),
      ContextOut = ContextIn
  ; Tail1 == closed ->
      require_no_extra_fields(Only2),
      unify(Tail2, record_type(Only1, closed), ContextIn, ContextOut)
  ; Tail2 == closed ->
      require_no_extra_fields(Only1),
      unify(Tail1, record_type(Only2, closed), ContextIn, ContextOut)
  ; Tail1 == Tail2 ->
      % The same open row cannot be extended two different ways.
      require_no_extra_fields(Only1),
      require_no_extra_fields(Only2),
      ContextOut = ContextIn
  ; % Two distinct row variables: link both through one fresh common tail.
    fresh_common_tail(Tail1, Tail2, ContextIn, CommonTail, Context1),
    unify(Tail1, record_type(Only2, CommonTail), Context1, Context2),
    unify(Tail2, record_type(Only1, CommonTail), Context2, ContextOut)
  ).

require_no_extra_fields([]) :- !.
require_no_extra_fields(Fields) :-
  findall(Key, member(record_field(_, Key, _), Fields), Keys),
  throw(analysis_error(record_field_mismatch(Keys))).

% A fresh row variable for the shared tail, born at the shallower of the two
% tails' levels so it generalises no more eagerly than they would.
fresh_common_tail(unification_variable(Id1), unification_variable(Id2),
                  context(NextId, Store), unification_variable(NextId),
                  context(NextId1, Store1)) :-
  get_assoc(Id1, Store, unsolved(Level1)),
  get_assoc(Id2, Store, unsolved(Level2)),
  ( Level1 =< Level2 -> Level = Level1 ; Level = Level2 ),
  NextId1 is NextId + 1,
  put_assoc(NextId, Store, unsolved(Level), Store1).

% bind_unification_variable(+Id, +Type, +ContextIn, -ContextOut).
%
% Solve `Id` to `Type`.  If `Id` carries a BOUND (a proper generic
% parameter's declared `<A: Bound>` -- see `any_bound/3`), the solution must
% SATISFY it.  This is the ONE place every solution to a bounded generic
% variable passes through, no matter how it got here -- a call argument, an
% annotation, a nested structural unification deep inside a record/function
% shape, a chain of aliased variables -- so it is the correct (and only
% necessary) place to enforce it; there is no need to track "obligations"
% separately at each call site.
bind_unification_variable(Id, Type, ContextIn, ContextOut) :-
  ContextIn = context(_, Store),
  get_assoc(Id, Store, unsolved(Level)),
  occurs_check_and_adjust_levels(Id, Level, Type, ContextIn, context(NextId, Store1)),
  put_assoc(Id, Store1, solved(Type), Store2),
  Context1 = context(NextId, Store2),
  any_bound(Context1, Id, Bound),
  ( Bound == no_bound ->
      ContextOut = Context1
  ; subsume(Type, Bound, Level, Context1, ContextOut)
  ).

% occurs_check_and_adjust_levels(+Id, +MaxLevel, +Type, +ContextIn, -ContextOut).
occurs_check_and_adjust_levels(Id, MaxLevel, Type, ContextIn, ContextOut) :-
  resolve_head(Type, ContextIn, Resolved),
  ( Resolved = unification_variable(Other) ->
      ( Other =:= Id ->
          throw(analysis_error(occurs_check(Id)))
      ; ContextIn = context(NextId, Store),
        get_assoc(Other, Store, unsolved(OtherLevel)),
        ( OtherLevel > MaxLevel ->
            put_assoc(Other, Store, unsolved(MaxLevel), Store1),
            ContextOut = context(NextId, Store1)
        ; ContextOut = ContextIn
        )
      )
  ; Resolved = function_type(Parameters, Return) ->
      occurs_check_and_adjust_levels_list(Id, MaxLevel, Parameters, ContextIn, Context1),
      occurs_check_and_adjust_levels(Id, MaxLevel, Return, Context1, ContextOut)
  ; Resolved = record_type(Fields, Tail) ->
      field_monotypes(Fields, Monotypes),
      occurs_check_and_adjust_levels_list(Id, MaxLevel, Monotypes, ContextIn, Context1),
      occurs_check_and_adjust_levels(Id, MaxLevel, Tail, Context1, ContextOut)
  ; Resolved = type_constructor(_, Arguments) ->
      occurs_check_and_adjust_levels_list(Id, MaxLevel, Arguments, ContextIn, ContextOut)
  ; Resolved = type_application(Head, Arguments) ->
      occurs_check_and_adjust_levels(Id, MaxLevel, Head, ContextIn, Context1),
      occurs_check_and_adjust_levels_list(Id, MaxLevel, Arguments, Context1, ContextOut)
  ; Resolved = forall_type(_BoundIds, Body) ->
      occurs_check_and_adjust_levels(Id, MaxLevel, Body, ContextIn, ContextOut)
  ; Resolved = type_lambda(_BoundIds, Body) ->
      occurs_check_and_adjust_levels(Id, MaxLevel, Body, ContextIn, ContextOut)
  ; Resolved = skolem(_SkolemId, SkolemLevel, SkolemName) ->
      % ESCAPE CHECK.  Binding a variable born at `MaxLevel` to a skolem from a
      % DEEPER scope (a larger level) would let that skolem leak outside the
      % polymorphic context that introduced it -- exactly the unsoundness
      % skolemisation guards against.
      ( SkolemLevel > MaxLevel ->
          throw(analysis_error(polymorphic_type_escapes(SkolemName)))
      ; ContextOut = ContextIn
      )
  ; Resolved = intersection_type(Members) ->
      % Same treatment as `type_constructor`'s Arguments just above: walk
      % every member so that binding a variable to (or through) an
      % intersection still correctly threads the occurs check and the level
      % ESCAPE CHECK into whatever is nested inside each member -- e.g. a
      % module ascribed to `B + C` where `B` or `C` itself mentions a still-
      % unsolved variable or a skolem from a deeper scope.
      occurs_check_and_adjust_levels_list(Id, MaxLevel, Members, ContextIn, ContextOut)
  ; ContextOut = ContextIn                 % base type, `closed` or constructor_ref
  ).

occurs_check_and_adjust_levels_list(_, _, [], Context, Context).
occurs_check_and_adjust_levels_list(Id, MaxLevel, [Type | Types], ContextIn, ContextOut) :-
  occurs_check_and_adjust_levels(Id, MaxLevel, Type, ContextIn, Context1),
  occurs_check_and_adjust_levels_list(Id, MaxLevel, Types, Context1, ContextOut).

% ---------------------------------------------------------------------------
% Generalisation and instantiation (let-polymorphism, via levels)
% ---------------------------------------------------------------------------

% generalize(+Type, +OuterLevel, +Context, -Scheme, -Context).
%
% The quantifiers are ordered by ASCENDING variable id, i.e. by creation
% order.  This makes the scheme's quantifier list positional: a function's
% explicitly declared type parameters (`<A B>(..)`) mint their variables, in
% declaration order, before any variable of the parameter list or body, so
% they come out first and in source order -- which is what lets a call site
% supply explicit type arguments positionally (see instantiate_positional).
generalize(Type, OuterLevel, Context, type_scheme(QuantifiedIds, Body), Context) :-
  fully_resolve(Type, Context, Resolved),
  collect_unification_variable_ids(Resolved, [], AllIds),
  include_generalizable(AllIds, OuterLevel, Context, Generalizable),
  sort(Generalizable, QuantifiedIds),
  abstract_quantified_variables(Resolved, QuantifiedIds, Body).

% scheme_free_unification_variables(+Scheme, -Ids).
%
% The unification-variable ids that remain FREE in a scheme's body (i.e. were
% not generalised away).  A scheme with none is self-contained and portable
% to another module's context; one with free variables is ambiguous and
% cannot be exported.  The body is assumed already fully-resolved (as
% `generalize/5` leaves it).
scheme_free_unification_variables(type_scheme(_BoundIds, Body), Ids) :-
  collect_unification_variable_ids(Body, [], Ids).

% collect_quantified_ids(+Type, -Ids).
%
% Every `quantified_variable`/`forall_type`-bound id reachable in a resolved
% hover type -- used to build a names/bounds table for RENDERING (see
% `quantified_name_table/3`), since a hover entry travels far from the
% analyser's own `Context` (across module boundaries, into the LSP query
% layer) by the time it is displayed, so the lookup this needs has to be
% packaged alongside the type itself rather than done lazily against Context.
collect_quantified_ids(Type, Ids) :-
  collect_quantified_ids(Type, [], Ids0),
  sort(Ids0, Ids).

collect_quantified_ids(Type, Accumulator, Ids) :-
  ( Type = quantified_variable(Id) ->
      ( memberchk(Id, Accumulator) -> Ids = Accumulator ; Ids = [Id | Accumulator] )
  ; Type = function_type(Parameters, Return) ->
      collect_quantified_ids_list(Parameters, Accumulator, Accumulator1),
      collect_quantified_ids(Return, Accumulator1, Ids)
  ; Type = record_type(Fields, Tail) ->
      field_monotypes(Fields, Monotypes),
      collect_quantified_ids_list(Monotypes, Accumulator, Accumulator1),
      collect_quantified_ids(Tail, Accumulator1, Ids)
  ; Type = type_constructor(_, Arguments) ->
      collect_quantified_ids_list(Arguments, Accumulator, Ids)
  ; Type = type_application(Head, Arguments) ->
      collect_quantified_ids(Head, Accumulator, Accumulator1),
      collect_quantified_ids_list(Arguments, Accumulator1, Ids)
  ; Type = forall_type(BoundIds, Body) ->
      append(BoundIds, Accumulator, Accumulator1),
      collect_quantified_ids(Body, Accumulator1, Ids)
  ; Type = type_lambda(_BoundIds, Body) ->
      collect_quantified_ids(Body, Accumulator, Ids)
  ; Type = intersection_type(Members) ->
      collect_quantified_ids_list(Members, Accumulator, Ids)
  ; Ids = Accumulator
  ).

collect_quantified_ids_list([], Accumulator, Accumulator).
collect_quantified_ids_list([Type | Types], Accumulator, Ids) :-
  collect_quantified_ids(Type, Accumulator, Accumulator1),
  collect_quantified_ids_list(Types, Accumulator1, Ids).

% quantified_name_table(+Context, +Ids, -Table).
%
% Table = list of `Id - Name - Bound` triples (`Bound` itself fully resolved,
% since it may still contain unification variables solved after it was first
% recorded), one per id -- the self-contained payload hover rendering needs
% to print `<A: Logger + Named>` without access to the live analyser Context.
quantified_name_table(_Context, [], []).
quantified_name_table(Context, [Id | Ids], [Id - Name - ResolvedBound | Rest]) :-
  variable_bound_info(Context, Id, Name, Bound),
  ( Bound == no_bound -> ResolvedBound = no_bound ; fully_resolve(Bound, Context, ResolvedBound) ),
  quantified_name_table(Context, Ids, Rest).

collect_unification_variable_ids(Type, Accumulator, Ids) :-
  ( Type = unification_variable(Id) ->
      ( memberchk(Id, Accumulator) -> Ids = Accumulator ; Ids = [Id | Accumulator] )
  ; Type = function_type(Parameters, Return) ->
      collect_unification_variable_ids_list(Parameters, Accumulator, Accumulator1),
      collect_unification_variable_ids(Return, Accumulator1, Ids)
  ; Type = record_type(Fields, Tail) ->
      field_monotypes(Fields, Monotypes),
      collect_unification_variable_ids_list(Monotypes, Accumulator, Accumulator1),
      collect_unification_variable_ids(Tail, Accumulator1, Ids)
  ; Type = type_constructor(_, Arguments) ->
      collect_unification_variable_ids_list(Arguments, Accumulator, Ids)
  ; Type = type_application(Head, Arguments) ->
      collect_unification_variable_ids(Head, Accumulator, Accumulator1),
      collect_unification_variable_ids_list(Arguments, Accumulator1, Ids)
  ; Type = forall_type(_BoundIds, Body) ->
      collect_unification_variable_ids(Body, Accumulator, Ids)
  ; Type = type_lambda(_BoundIds, Body) ->
      collect_unification_variable_ids(Body, Accumulator, Ids)
  ; Type = intersection_type(Members) ->
      % This is the one that matters most in practice: a module ascribed to
      % `B + C` (see infer.pl's module clause) has `intersection_type([...])`
      % as its ACTUAL exposed type, which then gets `generalize/5`'d exactly
      % like any other value's type.  `generalize/5` finds what to quantify
      % by calling THIS predicate first (`collect_unification_variable_ids`)
      % -- if it didn't know to look inside an intersection's members, any
      % still-free variable living in `B` or `C` (e.g. from a generic
      % module type) would never be discovered, and so would never be
      % generalized -- it would stay a bare, ungeneralized unification
      % variable, silently shared (and wrongly unified) across every future
      % use of that module, instead of being properly abstracted per use.
      collect_unification_variable_ids_list(Members, Accumulator, Ids)
  ; Ids = Accumulator
  ).

collect_unification_variable_ids_list([], Accumulator, Accumulator).
collect_unification_variable_ids_list([Type | Types], Accumulator, Ids) :-
  collect_unification_variable_ids(Type, Accumulator, Accumulator1),
  collect_unification_variable_ids_list(Types, Accumulator1, Ids).

include_generalizable([], _, _, []).
include_generalizable([Id | Ids], OuterLevel, Context, Result) :-
  Context = context(_, Store),
  get_assoc(Id, Store, unsolved(Level)),
  ( Level > OuterLevel ->
      Result = [Id | Rest]
  ; Result = Rest
  ),
  include_generalizable(Ids, OuterLevel, Context, Rest).

abstract_quantified_variables(Type, QuantifiedIds, Out) :-
  ( Type = unification_variable(Id) ->
      ( memberchk(Id, QuantifiedIds) -> Out = quantified_variable(Id) ; Out = Type )
  ; Type = function_type(Parameters, Return) ->
      abstract_quantified_variables_list(Parameters, QuantifiedIds, Parameters1),
      abstract_quantified_variables(Return, QuantifiedIds, Return1),
      Out = function_type(Parameters1, Return1)
  ; Type = record_type(Fields, Tail) ->
      abstract_fields(Fields, QuantifiedIds, Fields1),
      abstract_quantified_variables(Tail, QuantifiedIds, Tail1),
      Out = record_type(Fields1, Tail1)
  ; Type = type_constructor(Name, Arguments) ->
      abstract_quantified_variables_list(Arguments, QuantifiedIds, Arguments1),
      Out = type_constructor(Name, Arguments1)
  ; Type = type_application(Head, Arguments) ->
      abstract_quantified_variables(Head, QuantifiedIds, Head1),
      abstract_quantified_variables_list(Arguments, QuantifiedIds, Arguments1),
      Out = type_application(Head1, Arguments1)
  ; Type = forall_type(BoundIds, Body) ->
      abstract_quantified_variables(Body, QuantifiedIds, Body1),
      Out = forall_type(BoundIds, Body1)
  ; Type = type_lambda(BoundIds, Body) ->
      abstract_quantified_variables(Body, QuantifiedIds, Body1),
      Out = type_lambda(BoundIds, Body1)
  ; Type = intersection_type(Members) ->
      % The other half of `generalize/5`'s two-step dance: having COLLECTED
      % which variable ids are being generalized (via
      % `collect_unification_variable_ids`, see the comment there), this
      % step re-walks the same structure REPLACING each of those ids with
      % `quantified_variable(Id)` wherever it occurs -- including inside an
      % intersection's members, which is exactly why that collection step
      % had to look inside them too: collecting an id but never abstracting
      % its occurrence would leave a bare unification variable id sitting
      % inside the "generalized" scheme, which is not a valid scheme body.
      abstract_quantified_variables_list(Members, QuantifiedIds, Members1),
      Out = intersection_type(Members1)
  ; Out = Type
  ).

abstract_quantified_variables_list([], _, []).
abstract_quantified_variables_list([Type | Types], QuantifiedIds, [Out | Outs]) :-
  abstract_quantified_variables(Type, QuantifiedIds, Out),
  abstract_quantified_variables_list(Types, QuantifiedIds, Outs).

abstract_fields([], _, []).
abstract_fields([record_field(Mutability, Key, Type) | Fields], QuantifiedIds,
                [record_field(Mutability1, Key, Type1) | Outs]) :-
  abstract_quantified_variables(Mutability, QuantifiedIds, Mutability1),
  abstract_quantified_variables(Type, QuantifiedIds, Type1),
  abstract_fields(Fields, QuantifiedIds, Outs).

% instantiate(+Scheme, +Level, +ContextIn, -Type, -ContextOut).
instantiate(type_scheme(QuantifiedIds, Body), Level, ContextIn, Type, ContextOut) :-
  fresh_quantified_mapping(QuantifiedIds, Level, ContextIn, Mapping, ContextOut),
  substitute_quantified_variables(Body, Mapping, Type).

% instantiate_positional(+Scheme, +Provided, +Level, +ContextIn, -Type, -ContextOut).
%
% Instantiate with EXPLICIT type arguments: the first k quantifiers (in the
% scheme's positional order -- see generalize/5) are replaced by the k
% provided types; every remaining quantifier gets a fresh variable as in
% instantiate/5, so trailing arguments may be omitted and are then inferred.
% (An argument hole `_` is converted to a fresh variable by the caller, so it
% arrives here as an ordinary type.)  The caller checks k does not exceed the
% quantifier count.
instantiate_positional(type_scheme(QuantifiedIds, Body), Provided, Level, ContextIn, Type, ContextOut) :-
  positional_quantified_mapping(QuantifiedIds, Provided, Level, ContextIn, Mapping, ContextOut),
  substitute_quantified_variables(Body, Mapping, Type).

% Each fresh id minted below INHERITS the quantified id's name/bound (even
% when the bound is `no_bound`, so a plain `<A>`'s name still survives for
% hover through re-instantiation) -- see `record_variable_bound/5`.  A
% PROVIDED type argument is not a variable this predicate mints, so its bound
% (if any) is checked immediately via `subsume/5` rather than propagated.
positional_quantified_mapping([], _, _Level, Context, [], Context).
positional_quantified_mapping([Quantified | Rest], [], Level, ContextIn,
                              [Quantified - Fresh | Mapping], ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Fresh, Context1),
  Fresh = unification_variable(FreshId),
  variable_bound_info(Context1, Quantified, Name, Bound),
  record_variable_bound(Context1, FreshId, Name, Bound, Context2),
  positional_quantified_mapping(Rest, [], Level, Context2, Mapping, ContextOut).
positional_quantified_mapping([Quantified | Rest], [Provided | Others], Level, ContextIn,
                              [Quantified - Provided | Mapping], ContextOut) :-
  any_bound(ContextIn, Quantified, Bound),
  ( Bound == no_bound ->
      Context1 = ContextIn
  ; subsume(Provided, Bound, Level, ContextIn, Context1)
  ),
  positional_quantified_mapping(Rest, Others, Level, Context1, Mapping, ContextOut).

fresh_quantified_mapping([], _, Context, [], Context).
fresh_quantified_mapping([Quantified | Rest], Level, ContextIn,
                         [Quantified - Fresh | Mapping], ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Fresh, Context1),
  Fresh = unification_variable(FreshId),
  variable_bound_info(Context1, Quantified, Name, Bound),
  record_variable_bound(Context1, FreshId, Name, Bound, Context2),
  fresh_quantified_mapping(Rest, Level, Context2, Mapping, ContextOut).

substitute_quantified_variables(Type, Mapping, Out) :-
  ( Type = quantified_variable(Quantified) ->
      ( memberchk(Quantified - Fresh, Mapping) -> Out = Fresh ; Out = Type )
  ; Type = function_type(Parameters, Return) ->
      substitute_quantified_variables_list(Parameters, Mapping, Parameters1),
      substitute_quantified_variables(Return, Mapping, Return1),
      Out = function_type(Parameters1, Return1)
  ; Type = record_type(Fields, Tail) ->
      substitute_fields(Fields, Mapping, Fields1),
      substitute_quantified_variables(Tail, Mapping, Tail1),
      Out = record_type(Fields1, Tail1)
  ; Type = type_constructor(Name, Arguments) ->
      substitute_quantified_variables_list(Arguments, Mapping, Arguments1),
      Out = type_constructor(Name, Arguments1)
  ; Type = type_application(Head, Arguments) ->
      substitute_quantified_variables(Head, Mapping, Head1),
      substitute_quantified_variables_list(Arguments, Mapping, Arguments1),
      Out = type_application(Head1, Arguments1)
  ; Type = forall_type(BoundIds, Body) ->
      % The bound ids are globally unique, so no mapping key can capture them;
      % recurse into the body to substitute the OUTER quantified variables.
      substitute_quantified_variables(Body, Mapping, Body1),
      Out = forall_type(BoundIds, Body1)
  ; Type = type_lambda(BoundIds, Body) ->
      substitute_quantified_variables(Body, Mapping, Body1),
      Out = type_lambda(BoundIds, Body1)
  ; Type = intersection_type(Members) ->
      % Used by `instantiate`/`instantiate_positional` -- e.g. when a module
      % ascribed to `B + C` is used (or explicitly type-applied, `Combo<..>`),
      % its scheme's quantifiers get replaced throughout its whole type,
      % which includes reaching inside each intersection member the same way
      % it reaches inside a `type_constructor`'s Arguments.
      substitute_quantified_variables_list(Members, Mapping, Members1),
      Out = intersection_type(Members1)
  ; Out = Type
  ).

substitute_quantified_variables_list([], _, []).
substitute_quantified_variables_list([Type | Types], Mapping, [Out | Outs]) :-
  substitute_quantified_variables(Type, Mapping, Out),
  substitute_quantified_variables_list(Types, Mapping, Outs).

substitute_fields([], _, []).
substitute_fields([record_field(Mutability, Key, Type) | Fields], Mapping,
                  [record_field(Mutability1, Key, Type1) | Outs]) :-
  substitute_quantified_variables(Mutability, Mapping, Mutability1),
  substitute_quantified_variables(Type, Mapping, Type1),
  substitute_fields(Fields, Mapping, Outs).

% substitute_skolems(+Type, +Mapping, -Out).
%
% Replace `skolem(Id, _, _)` with its mapped replacement for every `Id - Type`
% pair in Mapping; skolems outside the mapping are left alone.  Used when a
% function literal's explicit generics -- checked RIGIDLY against the body as
% skolems -- are swapped back to flexible variables in the function's
% resulting type, so it generalises (or instantiates, when used inline) like
% any inferred type.  The input is assumed fully resolved.
substitute_skolems(Type, Mapping, Out) :-
  ( Type = skolem(Id, _, _) ->
      ( memberchk(Id - Replacement, Mapping) -> Out = Replacement ; Out = Type )
  ; Type = function_type(Parameters, Return) ->
      substitute_skolems_list(Parameters, Mapping, Parameters1),
      substitute_skolems(Return, Mapping, Return1),
      Out = function_type(Parameters1, Return1)
  ; Type = record_type(Fields, Tail) ->
      substitute_skolems_fields(Fields, Mapping, Fields1),
      substitute_skolems(Tail, Mapping, Tail1),
      Out = record_type(Fields1, Tail1)
  ; Type = type_constructor(Name, Arguments) ->
      substitute_skolems_list(Arguments, Mapping, Arguments1),
      Out = type_constructor(Name, Arguments1)
  ; Type = type_application(Head, Arguments) ->
      substitute_skolems(Head, Mapping, Head1),
      substitute_skolems_list(Arguments, Mapping, Arguments1),
      Out = type_application(Head1, Arguments1)
  ; Type = forall_type(BoundIds, Body) ->
      substitute_skolems(Body, Mapping, Body1),
      Out = forall_type(BoundIds, Body1)
  ; Type = type_lambda(BoundIds, Body) ->
      substitute_skolems(Body, Mapping, Body1),
      Out = type_lambda(BoundIds, Body1)
  ; Type = intersection_type(Members) ->
      % Used when a generic function's (or, per this project, a generic
      % MODULE's -- see the module type-parameter work later in this plan)
      % rigid skolems are swapped back to flexible variables in its result
      % type before that type is generalized.  If the result type happens to
      % be (or contain) an intersection -- e.g. a generic module ascribed to
      % a module type that itself mentions the module's own type parameter --
      % the swap has to reach inside its members too, or a rigid skolem
      % would be left stranded where a flexible variable was expected.
      substitute_skolems_list(Members, Mapping, Members1),
      Out = intersection_type(Members1)
  ; Out = Type
  ).

substitute_skolems_list([], _, []).
substitute_skolems_list([Type | Types], Mapping, [Out | Outs]) :-
  substitute_skolems(Type, Mapping, Out),
  substitute_skolems_list(Types, Mapping, Outs).

substitute_skolems_fields([], _, []).
substitute_skolems_fields([record_field(Mutability, Key, Type) | Fields], Mapping,
                          [record_field(Mutability1, Key, Type1) | Outs]) :-
  substitute_skolems(Mutability, Mapping, Mutability1),
  substitute_skolems(Type, Mapping, Type1),
  substitute_skolems_fields(Fields, Mapping, Outs).

% ---------------------------------------------------------------------------
% Rank-N: skolemisation, instantiation and subsumption
% ---------------------------------------------------------------------------

% instantiate_forall(+ForallType, +Level, +ContextIn, -OpenedType, -ContextOut).
%
% Open a polytype by replacing its bound variables with FRESH UNIFICATION
% variables at `Level` -- used when a polymorphic value is used at a specific
% (as-yet-unknown) type, e.g. applying a polymorphic function.
instantiate_forall(forall_type(BoundIds, Body), Level, ContextIn, OpenedType, ContextOut) :-
  fresh_quantified_mapping(BoundIds, Level, ContextIn, Mapping, ContextOut),
  substitute_quantified_variables(Body, Mapping, OpenedType).

% instantiate_forall_positional(+ForallType, +Provided, +Level, +ContextIn, -OpenedType, -ContextOut).
%
% Open a polytype with EXPLICIT type arguments bound positionally to its
% first bound variables (a `forall_type` keeps its bound ids in source
% order); the rest are opened fresh, exactly as in instantiate_positional/6.
instantiate_forall_positional(forall_type(BoundIds, Body), Provided, Level, ContextIn, OpenedType, ContextOut) :-
  positional_quantified_mapping(BoundIds, Provided, Level, ContextIn, Mapping, ContextOut),
  substitute_quantified_variables(Body, Mapping, OpenedType).

% skolemize_forall(+BoundIds, +Body, +Level, +ContextIn, -SkolemBody, -ContextOut).
%
% Open a polytype by replacing its bound variables with FRESH RIGID SKOLEMS at
% `Level` -- used when CHECKING that a value really has a polymorphic type.
skolemize_forall(BoundIds, Body, Level, ContextIn, SkolemBody, ContextOut) :-
  fresh_skolem_mapping(BoundIds, Level, ContextIn, Mapping, ContextOut),
  substitute_quantified_variables(Body, Mapping, SkolemBody).

fresh_skolem_mapping([], _Level, Context, [], Context).
fresh_skolem_mapping([Id | Ids], Level, ContextIn, [Id - skolem(SkolemId, Level, Name) | Mapping], ContextOut) :-
  fresh_bound_id(ContextIn, SkolemId, Context1),
  bound_id_name(ContextIn, Id, Name),
  fresh_skolem_mapping(Ids, Level, Context1, Mapping, ContextOut).

% subsume(+ActualType, +ExpectedType, +Level, +ContextIn, -ContextOut).
%
% The directed "ActualType is at least as polymorphic as ExpectedType" check
% (PJ et al. JFP'07 `subsCheck`; DK ICFP'13 subtyping).  It is the rank-N
% generalisation of `unify`: a more-polymorphic actual is fine where a less-
% polymorphic type is expected, but not the reverse.  We INSTANTIATE the
% actual (its `forall` may be specialised), SKOLEMISE the expected (it must
% hold for an arbitrary type), and are CONTRAVARIANT in function arguments.
% Deep skolemisation falls out of recursing through function results.
subsume(ActualType, ExpectedType, Level, ContextIn, ContextOut) :-
  resolve_head(ActualType, ContextIn, Actual),
  resolve_head(ExpectedType, ContextIn, Expected),
  subsume_resolved(Actual, Expected, Level, ContextIn, ContextOut).

% Actual is a polytype: instantiate it, then keep going.
subsume_resolved(forall_type(BoundIds, Body), Expected, Level, ContextIn, ContextOut) :- !,
  instantiate_forall(forall_type(BoundIds, Body), Level, ContextIn, Opened, Context1),
  subsume(Opened, Expected, Level, Context1, ContextOut).
% Expected is a polytype: skolemise it one level DEEPER (so the skolems are
% rigid within the check and the level escape check guards their scope), then
% check the actual against the skolemised body.
subsume_resolved(Actual, forall_type(BoundIds, Body), Level, ContextIn, ContextOut) :- !,
  Level1 is Level + 1,
  skolemize_forall(BoundIds, Body, Level1, ContextIn, SkolemBody, Context1),
  subsume(Actual, SkolemBody, Level1, Context1, ContextOut).
% EXPECTED is a still-unresolved flexible variable: there is no shape yet to
% check Actual's capabilities AGAINST, so subsumption reduces to plain
% unification -- binding Expected to Actual's WHOLE type (via
% `bind_unification_variable/4`, which is exactly where a BOUNDED Expected
% would itself get enforced, see its own doc comment).  This must be tried
% BEFORE the ACTUAL-is-intersection width-subtyping rule below: without this
% clause, an unconstrained Expected meeting an intersection Actual (e.g.
% instantiating a bounded generic `<A: Logger + Named>` at a call site, where
% the call argument's own type happens to be an intersection too) would fall
% into `subsume_any_member`'s per-member backtracking, which tries binding
% Expected to just ONE member at a time -- succeeding or failing depending on
% which member is tried first, rather than being bound to Actual as a whole.
subsume_resolved(Actual, unification_variable(Id), _Level, ContextIn, ContextOut) :- !,
  unify(Actual, unification_variable(Id), ContextIn, ContextOut).
% Both functions: contravariant in arguments (expected ⊑ actual), covariant in
% the result.  This is what lets a less-polymorphic argument position accept a
% more-polymorphic expectation, and propagates rank-N through nested arrows.
subsume_resolved(function_type(ActualParams, ActualReturn),
                 function_type(ExpectedParams, ExpectedReturn), Level, ContextIn, ContextOut) :-
  same_length(ActualParams, ExpectedParams), !,
  subsume_arguments(ExpectedParams, ActualParams, Level, ContextIn, Context1),
  subsume(ActualReturn, ExpectedReturn, Level, Context1, ContextOut).
% BOTH sides are intersections.  This is checked as its OWN case, explicitly,
% rather than left to fall out of the two single-sided intersection rules
% below composing with each other -- composing them would require ONE actual
% member to single-handedly cover the WHOLE expected intersection, which is
% too strong: a value that IS exactly both `B` and `D` correctly satisfies
% "needs both B and D", but neither `B` alone nor `D` alone does, so the
% "actual member vs whole expected intersection" composition would wrongly
% reject that case.  The textbook-correct rule (Actual <: Expected between
% two intersections) is WIDTH-then-MEET: for every REQUIRED capability
% (every member of ExpectedMembers), SOME possessed capability (some member
% of ActualMembers) must cover it -- different required members are allowed
% to be covered by different possessed members.
subsume_resolved(intersection_type(ActualMembers), intersection_type(ExpectedMembers),
                 Level, ContextIn, ContextOut) :- !,
  subsume_every_required(ExpectedMembers, ActualMembers, Level, ContextIn, ContextOut).
% ACTUAL is an intersection, EXPECTED is a single ordinary type: WIDTH
% subtyping -- possessing MORE capabilities (being both B and C) trivially
% satisfies a request for just ONE of them, as long as SOME single member
% alone already would (tried via backtracking over `subsume_any_member`,
% below).  This is what lets a module ascribed to `B + C` flow anywhere a
% plain `B`, or a plain `C`, is independently expected.
subsume_resolved(intersection_type(ActualMembers), Expected, Level, ContextIn, ContextOut) :- !,
  subsume_any_member(ActualMembers, Expected, Level, ContextIn, ContextOut).
% EXPECTED is an intersection, ACTUAL is a single ordinary type: MEET
% semantics -- to satisfy "must be both B and C", Actual (on its own) must
% independently satisfy EVERY member.  Unlike the ACTUAL-is-intersection
% case above, this is a plain conjunction: there is no alternative to try, so
% a genuine failure on any one member should genuinely propagate (no
% catch/backtrack wrapper needed here, unlike `subsume_any_member`).
subsume_resolved(Actual, intersection_type(ExpectedMembers), Level, ContextIn, ContextOut) :- !,
  subsume_all_members(Actual, ExpectedMembers, Level, ContextIn, ContextOut).
% Anything else: there is no polymorphism left to peel, so plain unification is
% exactly the right (invariant) check.
subsume_resolved(Actual, Expected, _Level, ContextIn, ContextOut) :-
  unify(Actual, Expected, ContextIn, ContextOut).

subsume_arguments([], [], _Level, Context, Context).
subsume_arguments([Expected | Expecteds], [Actual | Actuals], Level, ContextIn, ContextOut) :-
  subsume(Expected, Actual, Level, ContextIn, Context1),
  subsume_arguments(Expecteds, Actuals, Level, Context1, ContextOut).

% For every required member (an ExpectedMembers entry), some possessed
% member (an ActualMembers entry) must subsume it -- see
% `subsume_any_member/5` for how "some" is tried safely (subsume THROWS on a
% genuine mismatch rather than merely failing, so trying alternatives needs
% to catch and retry, not rely on plain Prolog backtracking over a throw,
% which would abort the whole search instead of trying the next candidate).
subsume_every_required([], _ActualMembers, _Level, Context, Context).
subsume_every_required([Expected | Rest], ActualMembers, Level, ContextIn, ContextOut) :-
  subsume_any_member(ActualMembers, Expected, Level, ContextIn, Context1),
  subsume_every_required(Rest, ActualMembers, Level, Context1, ContextOut).

% Does `subsume(Candidate, Target, ...)` succeed for SOME Candidate in the
% list?  Tried in order; each attempt starts from a fresh `ContextIn` (a
% candidate that throws partway through leaves no partial bindings behind,
% same reasoning as `select_unifiable/5` above for `unify`).  Running out of
% candidates without success THROWS (never bare-fails) with a clear reason.
subsume_any_member([], Target, _Level, ContextIn, _ContextOut) :-
  fully_resolve(Target, ContextIn, ResolvedTarget),
  throw(analysis_error(no_intersection_member_subsumes(ResolvedTarget))).
subsume_any_member([Candidate | _Rest], Target, Level, ContextIn, ContextOut) :-
  catch(subsume(Candidate, Target, Level, ContextIn, ContextOut), analysis_error(_), fail), !.
subsume_any_member([_ | Rest], Target, Level, ContextIn, ContextOut) :-
  subsume_any_member(Rest, Target, Level, ContextIn, ContextOut).

% Does `Actual` (a single, non-intersection type) subsume EVERY member of
% ExpectedMembers?  A plain conjunction -- no alternatives to try, so a real
% mismatch on any one member propagates as-is (whatever `subsume/5` itself
% throws), rather than being caught and retried.
subsume_all_members(_Actual, [], _Level, Context, Context).
subsume_all_members(Actual, [Member | Rest], Level, ContextIn, ContextOut) :-
  subsume(Actual, Member, Level, ContextIn, Context1),
  subsume_all_members(Actual, Rest, Level, Context1, ContextOut).

% ---------------------------------------------------------------------------
% Reporting
% ---------------------------------------------------------------------------

% context_substitution(+Context, -Substitution).
context_substitution(Context, Substitution) :-
  Context = context(_, Store),
  assoc_to_list(Store, Pairs),
  solved_pairs(Pairs, Context, Substitution).

solved_pairs([], _, []).
solved_pairs([Id - solved(Type) | Pairs], Context, [Id = Resolved | Rest]) :- !,
  fully_resolve(Type, Context, Resolved),
  solved_pairs(Pairs, Context, Rest).
% Skip unsolved variables and non-variable entries (`bound_name(_)` records).
solved_pairs([_ - _ | Pairs], Context, Rest) :-
  solved_pairs(Pairs, Context, Rest).
