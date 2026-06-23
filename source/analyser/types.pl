:- module(types, [
  empty_context/1,
  fresh_unification_variable/4,
  resolve_head/3,
  fully_resolve/3,
  unify/4,
  generalize/5,
  instantiate/5,
  monomorphic_type_scheme/2,
  context_substitution/2
]).

/*  types.pl  --  Type language + level-based algorithmic context.

    Implements the level-based algorithmic type system of Fan, Xu & Xie,
    "Practical Type Inference with Levels" (PLDI'25), with let-generalisation
    as in Heeren, Hage & Swierstra (UU-CS-2002-031), extended with
    Remy/Wand-style ROW POLYMORPHISM for tuples (records).

    --------------------------------------------------------------------
    THE TYPE LANGUAGE
    --------------------------------------------------------------------
    A monotype is one of:

        number / boolean / string       base types
        readonly / mutable              base types, used only in the
                                        mutability slot of a tuple field
                                        (so mutability unifies like any type)
        unification_variable(Id)        an as-yet-unknown type/row; level and
                                        solution live in the context
        function_type(Params, Ret)      an n-ary function `(t1 .. tn) -> r`
        type_constructor(Name, Args)    a NOMINAL named type (see below)
        tuple_type(Fields, Tail)        a RECORD; see below

    TUPLES AS ROWS.  A `tuple_type(Fields, Tail)` is a record:

        Fields  a list of  tuple_field(Mutability, Key, Type)
                  Key is  index(N)   for a positional member, or
                          label(Name) for a labeled member.
        Tail    either `closed` (these are exactly the fields) or a
                unification variable -- a ROW VARIABLE standing for "any
                further fields".  Solving a row variable binds it to another
                `tuple_type(MoreFields, FurtherTail)`, so an open record is a
                chain that `flatten_tuple/4` collapses.

    A tuple LITERAL is closed.  A member access only requires "a record with
    at least this field" -- an open tail -- which is what makes functions
    like `(p) p.x` row-polymorphic: the row variable is generalised.

    NOMINAL vs STRUCTURAL.  `function_type` and `tuple_type` unify
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

%% empty_context(-Context).
empty_context(context(0, Store)) :-
  empty_assoc(Store).

%% fresh_unification_variable(+ContextIn, +Level, -Variable, -ContextOut).
fresh_unification_variable(context(Id, Store), Level, unification_variable(Id),
                           context(NextId, Store1)) :-
  NextId is Id + 1,
  put_assoc(Id, Store, unsolved(Level), Store1).

%% monomorphic_type_scheme(+Type, -Scheme).
monomorphic_type_scheme(Type, type_scheme([], Type)).

% ---------------------------------------------------------------------------
% Resolution (context application, Fig. 4)
% ---------------------------------------------------------------------------

%% resolve_head(+Type, +Context, -Resolved).
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
  ; Resolved = Type
  ).

%% fully_resolve(+Type, +Context, -Resolved).
%
% Deep context application, leaving no solved variables.  Tuple chains are
% flattened so the result is a single `tuple_type(AllFields, FinalTail)`.
fully_resolve(Type, Context, Resolved) :-
  resolve_head(Type, Context, Head),
  ( Head = function_type(Parameters, Return) ->
      fully_resolve_list(Parameters, Context, Parameters1),
      fully_resolve(Return, Context, Return1),
      Resolved = function_type(Parameters1, Return1)
  ; Head = tuple_type(_, _) ->
      flatten_tuple(Head, Context, Fields, Tail),
      fully_resolve_fields(Fields, Context, Fields1),
      Resolved = tuple_type(Fields1, Tail)
  ; Head = type_constructor(Name, Arguments) ->
      fully_resolve_list(Arguments, Context, Arguments1),
      Resolved = type_constructor(Name, Arguments1)
  ; Resolved = Head
  ).

fully_resolve_list([], _, []).
fully_resolve_list([Type | Types], Context, [Resolved | Rest]) :-
  fully_resolve(Type, Context, Resolved),
  fully_resolve_list(Types, Context, Rest).

% Resolve the mutability and type carried by each field, keeping the key.
fully_resolve_fields([], _, []).
fully_resolve_fields([tuple_field(Mutability, Key, Type) | Fields], Context,
                     [tuple_field(Mutability1, Key, Type1) | Rest]) :-
  fully_resolve(Mutability, Context, Mutability1),
  fully_resolve(Type, Context, Type1),
  fully_resolve_fields(Fields, Context, Rest).

% Collapse an open-record chain into its full field list and final tail.
% The tail is resolved to either `closed` or an unsolved unification variable.
flatten_tuple(tuple_type(Fields, Tail), Context, AllFields, FinalTail) :-
  resolve_head(Tail, Context, ResolvedTail),
  ( ResolvedTail = tuple_type(MoreFields, FurtherTail) ->
      flatten_tuple(tuple_type(MoreFields, FurtherTail), Context, RestFields, FinalTail),
      append(Fields, RestFields, AllFields)
  ; AllFields = Fields,
    FinalTail = ResolvedTail
  ).

% The monotypes carried by a field (its mutability and its type), used by the
% occurs check and variable collection, which treat both like any subtype.
field_monotypes([], []).
field_monotypes([tuple_field(Mutability, _, Type) | Fields], [Mutability, Type | Rest]) :-
  field_monotypes(Fields, Rest).

% ---------------------------------------------------------------------------
% Unification with level adjustment (Fig. 6)
% ---------------------------------------------------------------------------

%% unify(+Type1, +Type2, +ContextIn, -ContextOut).
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
% STRUCTURAL, row-polymorphic rule for tuples.
unify_resolved(tuple_type(Fields1, Tail1), tuple_type(Fields2, Tail2), ContextIn, ContextOut) :- !,
  flatten_tuple(tuple_type(Fields1, Tail1), ContextIn, AllFields1, FinalTail1),
  flatten_tuple(tuple_type(Fields2, Tail2), ContextIn, AllFields2, FinalTail2),
  unify_rows(AllFields1, FinalTail1, AllFields2, FinalTail2, ContextIn, ContextOut).
% NOMINAL rule: type constructors unify only when names match.
unify_resolved(type_constructor(Name, Arguments1), type_constructor(Name, Arguments2),
               ContextIn, ContextOut) :- !,
  ( same_length(Arguments1, Arguments2) ->
      unify_list(Arguments1, Arguments2, ContextIn, ContextOut)
  ; throw(analysis_error(type_constructor_arity_mismatch(Name, Arguments1, Arguments2)))
  ).
unify_resolved(TypeA, TypeB, ContextIn, _) :-
  fully_resolve(TypeA, ContextIn, ResolvedA),
  fully_resolve(TypeB, ContextIn, ResolvedB),
  throw(analysis_error(type_mismatch(ResolvedA, ResolvedB))).

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
  Field1 = tuple_field(_, Key, _),
  ( select_field(Key, Fields2, Field2, Fields2Rest) ->
      Common = [Field1 - Field2 | CommonRest],
      match_fields(Rest1, Fields2Rest, CommonRest, Only1, Only2)
  ; Only1 = [Field1 | Only1Rest],
    match_fields(Rest1, Fields2, Common, Only1Rest, Only2)
  ).

select_field(Key, [tuple_field(M, Key, T) | Rest], tuple_field(M, Key, T), Rest) :- !.
select_field(Key, [Other | Rest], Found, [Other | RestOut]) :-
  select_field(Key, Rest, Found, RestOut).

unify_common_fields([], Context, Context).
unify_common_fields([tuple_field(M1, _, T1) - tuple_field(M2, _, T2) | Rest], ContextIn, ContextOut) :-
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
      unify(Tail2, tuple_type(Only1, closed), ContextIn, ContextOut)
  ; Tail2 == closed ->
      require_no_extra_fields(Only1),
      unify(Tail1, tuple_type(Only2, closed), ContextIn, ContextOut)
  ; Tail1 == Tail2 ->
      % The same open row cannot be extended two different ways.
      require_no_extra_fields(Only1),
      require_no_extra_fields(Only2),
      ContextOut = ContextIn
  ; % Two distinct row variables: link both through one fresh common tail.
    fresh_common_tail(Tail1, Tail2, ContextIn, CommonTail, Context1),
    unify(Tail1, tuple_type(Only2, CommonTail), Context1, Context2),
    unify(Tail2, tuple_type(Only1, CommonTail), Context2, ContextOut)
  ).

require_no_extra_fields([]) :- !.
require_no_extra_fields(Fields) :-
  findall(Key, member(tuple_field(_, Key, _), Fields), Keys),
  throw(analysis_error(tuple_field_mismatch(Keys))).

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

%% bind_unification_variable(+Id, +Type, +ContextIn, -ContextOut).
bind_unification_variable(Id, Type, ContextIn, ContextOut) :-
  ContextIn = context(_, Store),
  get_assoc(Id, Store, unsolved(Level)),
  occurs_check_and_adjust_levels(Id, Level, Type, ContextIn, context(NextId, Store1)),
  put_assoc(Id, Store1, solved(Type), Store2),
  ContextOut = context(NextId, Store2).

%% occurs_check_and_adjust_levels(+Id, +MaxLevel, +Type, +ContextIn, -ContextOut).
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
  ; Resolved = tuple_type(Fields, Tail) ->
      field_monotypes(Fields, Monotypes),
      occurs_check_and_adjust_levels_list(Id, MaxLevel, Monotypes, ContextIn, Context1),
      occurs_check_and_adjust_levels(Id, MaxLevel, Tail, Context1, ContextOut)
  ; Resolved = type_constructor(_, Arguments) ->
      occurs_check_and_adjust_levels_list(Id, MaxLevel, Arguments, ContextIn, ContextOut)
  ; ContextOut = ContextIn                 % base type or `closed`: nothing to do
  ).

occurs_check_and_adjust_levels_list(_, _, [], Context, Context).
occurs_check_and_adjust_levels_list(Id, MaxLevel, [Type | Types], ContextIn, ContextOut) :-
  occurs_check_and_adjust_levels(Id, MaxLevel, Type, ContextIn, Context1),
  occurs_check_and_adjust_levels_list(Id, MaxLevel, Types, Context1, ContextOut).

% ---------------------------------------------------------------------------
% Generalisation and instantiation (let-polymorphism, via levels)
% ---------------------------------------------------------------------------

%% generalize(+Type, +OuterLevel, +Context, -Scheme, -Context).
generalize(Type, OuterLevel, Context, type_scheme(QuantifiedIds, Body), Context) :-
  fully_resolve(Type, Context, Resolved),
  collect_unification_variable_ids(Resolved, [], AllIds),
  include_generalizable(AllIds, OuterLevel, Context, QuantifiedIds),
  abstract_quantified_variables(Resolved, QuantifiedIds, Body).

collect_unification_variable_ids(Type, Accumulator, Ids) :-
  ( Type = unification_variable(Id) ->
      ( memberchk(Id, Accumulator) -> Ids = Accumulator ; Ids = [Id | Accumulator] )
  ; Type = function_type(Parameters, Return) ->
      collect_unification_variable_ids_list(Parameters, Accumulator, Accumulator1),
      collect_unification_variable_ids(Return, Accumulator1, Ids)
  ; Type = tuple_type(Fields, Tail) ->
      field_monotypes(Fields, Monotypes),
      collect_unification_variable_ids_list(Monotypes, Accumulator, Accumulator1),
      collect_unification_variable_ids(Tail, Accumulator1, Ids)
  ; Type = type_constructor(_, Arguments) ->
      collect_unification_variable_ids_list(Arguments, Accumulator, Ids)
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
  ; Type = tuple_type(Fields, Tail) ->
      abstract_fields(Fields, QuantifiedIds, Fields1),
      abstract_quantified_variables(Tail, QuantifiedIds, Tail1),
      Out = tuple_type(Fields1, Tail1)
  ; Type = type_constructor(Name, Arguments) ->
      abstract_quantified_variables_list(Arguments, QuantifiedIds, Arguments1),
      Out = type_constructor(Name, Arguments1)
  ; Out = Type
  ).

abstract_quantified_variables_list([], _, []).
abstract_quantified_variables_list([Type | Types], QuantifiedIds, [Out | Outs]) :-
  abstract_quantified_variables(Type, QuantifiedIds, Out),
  abstract_quantified_variables_list(Types, QuantifiedIds, Outs).

abstract_fields([], _, []).
abstract_fields([tuple_field(Mutability, Key, Type) | Fields], QuantifiedIds,
                [tuple_field(Mutability1, Key, Type1) | Outs]) :-
  abstract_quantified_variables(Mutability, QuantifiedIds, Mutability1),
  abstract_quantified_variables(Type, QuantifiedIds, Type1),
  abstract_fields(Fields, QuantifiedIds, Outs).

%% instantiate(+Scheme, +Level, +ContextIn, -Type, -ContextOut).
instantiate(type_scheme(QuantifiedIds, Body), Level, ContextIn, Type, ContextOut) :-
  fresh_quantified_mapping(QuantifiedIds, Level, ContextIn, Mapping, ContextOut),
  substitute_quantified_variables(Body, Mapping, Type).

fresh_quantified_mapping([], _, Context, [], Context).
fresh_quantified_mapping([Quantified | Rest], Level, ContextIn,
                         [Quantified - Fresh | Mapping], ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Fresh, Context1),
  fresh_quantified_mapping(Rest, Level, Context1, Mapping, ContextOut).

substitute_quantified_variables(Type, Mapping, Out) :-
  ( Type = quantified_variable(Quantified) ->
      ( memberchk(Quantified - Fresh, Mapping) -> Out = Fresh ; Out = Type )
  ; Type = function_type(Parameters, Return) ->
      substitute_quantified_variables_list(Parameters, Mapping, Parameters1),
      substitute_quantified_variables(Return, Mapping, Return1),
      Out = function_type(Parameters1, Return1)
  ; Type = tuple_type(Fields, Tail) ->
      substitute_fields(Fields, Mapping, Fields1),
      substitute_quantified_variables(Tail, Mapping, Tail1),
      Out = tuple_type(Fields1, Tail1)
  ; Type = type_constructor(Name, Arguments) ->
      substitute_quantified_variables_list(Arguments, Mapping, Arguments1),
      Out = type_constructor(Name, Arguments1)
  ; Out = Type
  ).

substitute_quantified_variables_list([], _, []).
substitute_quantified_variables_list([Type | Types], Mapping, [Out | Outs]) :-
  substitute_quantified_variables(Type, Mapping, Out),
  substitute_quantified_variables_list(Types, Mapping, Outs).

substitute_fields([], _, []).
substitute_fields([tuple_field(Mutability, Key, Type) | Fields], Mapping,
                  [tuple_field(Mutability1, Key, Type1) | Outs]) :-
  substitute_quantified_variables(Mutability, Mapping, Mutability1),
  substitute_quantified_variables(Type, Mapping, Type1),
  substitute_fields(Fields, Mapping, Outs).

% ---------------------------------------------------------------------------
% Reporting
% ---------------------------------------------------------------------------

%% context_substitution(+Context, -Substitution).
context_substitution(Context, Substitution) :-
  Context = context(_, Store),
  assoc_to_list(Store, Pairs),
  solved_pairs(Pairs, Context, Substitution).

solved_pairs([], _, []).
solved_pairs([Id - solved(Type) | Pairs], Context, [Id = Resolved | Rest]) :- !,
  fully_resolve(Type, Context, Resolved),
  solved_pairs(Pairs, Context, Rest).
solved_pairs([_ - unsolved(_) | Pairs], Context, Rest) :-
  solved_pairs(Pairs, Context, Rest).
