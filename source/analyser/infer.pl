:- module(infer, [
  infer_program/6,
  infer_program_accumulating/7,
  infer/8
]).

/*  infer.pl  --  The level-indexed inference judgement.

    This module walks the parser's AST and computes a type for every
    expression, threading the algorithmic context of `types.pl`.  It is
    mostly synthesis ("Algorithm W"-style) over the level-based rules of Fan,
    Xu & Xie (PLDI'25), with a CHECKING direction (`check_expr/8`) used where
    an expected type is known -- a definition/return annotation, or a function
    argument.  Checking is what supports predicative RANK-N polymorphism: a
    polytype expectation is skolemised and the node verified against it, so a
    polymorphic value can be checked rather than prematurely instantiated.

    The central judgement is

        infer(+Node, +Level, +InsideFunction,
              +Environment, +TypeEnvironment, +ContextIn, -Type, -ContextOut)

    read as:  under term environment `Environment` and the declared-type
    environment `TypeEnvironment`, at typing level `Level`, the expression
    `Node` synthesises type `Type`, taking the algorithmic context from
    `ContextIn` to `ContextOut`.

    `Environment` is the term context: an assoc from a variable name (its
    character list) to a tagged binding

        defined(Scheme)    -- a name fully in scope and usable anywhere.
        forward(Scheme)    -- a name defined *later* in the current
                              sequence; usable only inside a function body.

    `TypeEnvironment` is the read-only map of declared type constructors
    built by `type_environment.pl`; it is consulted whenever an annotation
    has to be converted to a monotype.

    `InsideFunction` (a boolean) records whether we are underneath a
    lambda; it gates forward references.

    --------------------------------------------------------------------
    LEVELS AND SCOPES
    --------------------------------------------------------------------
    The typing level tracks nesting depth.  A *definition* (`x = e`),
    this language's `let`, increments it.  A plain lambda keeps the level
    fixed and introduces monomorphic parameters; a lambda with explicit
    generics types its body one level deeper, where each generic is a
    rigid skolem confined by the escape check.
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).

:- use_module(types, [
  fresh_unification_variable/4,
  resolve_head/3,
  fully_resolve/3,
  unify/4,
  subsume/5,
  instantiate_forall/5,
  instantiate_forall_positional/6,
  skolemize_forall/6,
  generalize/5,
  substitute_skolems/3,
  instantiate/5,
  instantiate_positional/6,
  monomorphic_type_scheme/2
]).
:- use_module(operators, [
  unary_signature/4,
  binary_signature/7
]).
:- use_module(type_environment, [
  convert_annotation_type/6,
  bind_type_parameters_rigid/8,
  declared_function_scheme/6,
  instantiate_constructor/7,
  union_constructor_names/3,
  module_type_row_for/7,
  seed_externals/7
]).

% infer_program(+ProgramNode, +TypeEnvironment, +InitialEnvironment, +ContextIn, -Result, -FinalEnvironment).
%
% Entry point for a whole program: a sequence of top-level expressions
% evaluated at level 0.  `Result` is `program_type(LastType, ContextOut)`.
% `FinalEnvironment` is the term environment after the whole sequence, i.e.
% with every top-level definition bound to its generalised scheme -- the
% module system reads exported value schemes from it.
infer_program(program_node(Expressions), TypeEnvironment, InitialEnvironment, ContextIn,
              program_type(LastType, ContextOut), FinalEnvironment) :-
  infer_sequence(Expressions, 0, false, InitialEnvironment, TypeEnvironment, ContextIn, LastType, FinalEnvironment, ContextOut).

% infer_program_accumulating(+ProgramNode, +TypeEnvironment, +InitialEnvironment,
%                            +ContextIn, -Result, -FinalEnvironment, -Errors).
%
% Same inference as `infer_program/6` -- the SAME judgement, environment and
% unifier -- but instead of letting the first `analysis_error` propagate, each
% TOP-LEVEL item is wrapped so an error is RECORDED (`error_at(Span, Reason)`)
% and the walk continues with that name left as its forward placeholder.  This
% is what the LSP/incremental path uses to report errors in several definitions
% at once; the batch compiler keeps using the throwing `infer_program/6`.
% (One error per top-level item: a thrown error abandons that item's body.)
infer_program_accumulating(program_node(Expressions), TypeEnvironment, InitialEnvironment, ContextIn,
                           program_type(LastType, ContextOut), FinalEnvironment, Errors) :-
  prebind_forward(Expressions, 0, InitialEnvironment, TypeEnvironment, ContextIn, Environment1, Context1),
  walk_accumulating(Expressions, 0, false, Environment1, TypeEnvironment, Context1,
                    LastType, FinalEnvironment, ContextOut, [], ReverseErrors),
  reverse(ReverseErrors, Errors).

walk_accumulating([], _Level, _InsideFunction, Environment, _TypeEnvironment, Context,
                  record_type([], closed), Environment, Context, Errors, Errors).
walk_accumulating([Expression], Level, InsideFunction, Environment, TypeEnvironment, ContextIn,
                  ResultType, FinalEnvironment, ContextOut, ErrorsIn, ErrorsOut) :-
  try_item(Expression, Level, InsideFunction, Environment, TypeEnvironment, ContextIn,
           ResultType, FinalEnvironment, ContextOut, ErrorsIn, ErrorsOut).
walk_accumulating([Expression, Next | Rest], Level, InsideFunction, Environment, TypeEnvironment,
                  ContextIn, ResultType, FinalEnvironment, ContextOut, ErrorsIn, ErrorsOut) :-
  try_item(Expression, Level, InsideFunction, Environment, TypeEnvironment, ContextIn,
           _Type, Environment1, Context1, ErrorsIn, Errors1),
  walk_accumulating([Next | Rest], Level, InsideFunction, Environment1, TypeEnvironment,
                    Context1, ResultType, FinalEnvironment, ContextOut, Errors1, ErrorsOut).

% Infer one top-level item; on an analysis error, record it (with the item's
% span) and continue from the PRE-item environment/context so later items are
% still checked.  Reuses the ordinary `infer_sequence_item/9` (same rules).
try_item(Expression, Level, InsideFunction, Environment, TypeEnvironment, ContextIn,
         Type, EnvironmentOut, ContextOut, ErrorsIn, ErrorsOut) :-
  catch(
    ( infer_sequence_item(Expression, Level, InsideFunction, Environment, TypeEnvironment,
                          ContextIn, Type, EnvironmentOut, ContextOut),
      ErrorsOut = ErrorsIn ),
    analysis_error(Reason),
    ( EnvironmentOut = Environment, ContextOut = ContextIn, Type = record_type([], closed),
      item_span(Expression, Span),
      ErrorsOut = [error_at(Span, Reason) | ErrorsIn] )
  ).

item_span(definition_node(_, _, _, Span), Span) :- !.
item_span(destructuring_node(_, _, Span), Span) :- !.
item_span(external_node(_, _, _, Span), Span) :- !.
item_span(Node, Span) :- Node =.. Args, append(_, [Last], Args), Last = span(_, _), !, Span = Last.
item_span(_Node, span(0, 0)).

% ---------------------------------------------------------------------------
% Sequences: programs and blocks  (this is where `let` lives)
% ---------------------------------------------------------------------------

% infer_sequence(+Expressions, +Level, +InsideFunction, +Environment, +TypeEnvironment, +ContextIn, -ResultType, -FinalEnvironment, -ContextOut).
%
% A sequence is the scope shared by a group of definitions.  We first
% pre-bind every definition name as a `forward` placeholder (so earlier
% definitions may refer forward, from inside a function body), then walk
% the sequence left to right, generalising each definition as we pass it.
% Type declarations carry no value and are skipped here (they were already
% collected and validated into `TypeEnvironment`).  `FinalEnvironment` is the
% environment after the last item (with all definitions bound).
infer_sequence(Expressions, Level, InsideFunction, Environment, TypeEnvironment,
               ContextIn, ResultType, FinalEnvironment, ContextOut) :-
  prebind_forward(Expressions, Level, Environment, TypeEnvironment, ContextIn, Environment1, Context1),
  infer_sequence_walk(Expressions, Level, InsideFunction, Environment1, TypeEnvironment,
                      Context1, ResultType, FinalEnvironment, ContextOut).

% Pre-bind each value definition's name, tagged `forward`.  A fully annotated
% generic function literal contributes its DECLARED scheme, so a recursive
% use instantiates the signature polymorphically -- necessary now that the
% body is checked against rigid skolems, which may not leak into an
% outer-level placeholder.  Any other definition gets a fresh placeholder
% variable and recursion through it stays monomorphic, as before.  A bad
% annotation is ignored HERE (placeholder fallback) so the error surfaces at
% the definition item, which reports it with its span.
prebind_forward([], _Level, Environment, _TypeEnvironment, Context, Environment, Context).
prebind_forward([definition_node(identifier_node(Name, _), _, Value, _) | Expressions], Level,
                Environment, TypeEnvironment, ContextIn, EnvironmentOut, ContextOut) :- !,
  ( catch(declared_function_scheme(Value, TypeEnvironment, Level, ContextIn, DeclaredScheme, Context1),
          analysis_error(_),
          fail) ->
      Scheme = DeclaredScheme
  ; fresh_unification_variable(ContextIn, Level, Placeholder, Context1),
    monomorphic_type_scheme(Placeholder, Scheme)
  ),
  put_assoc(Name, Environment, forward(Scheme), Environment1),
  prebind_forward(Expressions, Level, Environment1, TypeEnvironment, Context1, EnvironmentOut, ContextOut).
prebind_forward([_ | Expressions], Level, Environment, TypeEnvironment, ContextIn, EnvironmentOut, ContextOut) :-
  prebind_forward(Expressions, Level, Environment, TypeEnvironment, ContextIn, EnvironmentOut, ContextOut).

% Walk the sequence, threading the (growing) environment and reporting the
% last expression's type.  An empty sequence has the unit type `()`.
infer_sequence_walk([], _Level, _InsideFunction, Environment, _TypeEnvironment,
                    Context, record_type([], closed), Environment, Context).
infer_sequence_walk([Expression], Level, InsideFunction, Environment, TypeEnvironment,
                    ContextIn, ResultType, FinalEnvironment, ContextOut) :-
  infer_sequence_item(Expression, Level, InsideFunction, Environment, TypeEnvironment,
                      ContextIn, ResultType, FinalEnvironment, ContextOut).
infer_sequence_walk([Expression, Next | Rest], Level, InsideFunction, Environment,
                    TypeEnvironment, ContextIn, ResultType, FinalEnvironment, ContextOut) :-
  infer_sequence_item(Expression, Level, InsideFunction, Environment, TypeEnvironment,
                      ContextIn, _Type, Environment1, Context1),
  infer_sequence_walk([Next | Rest], Level, InsideFunction, Environment1, TypeEnvironment,
                      Context1, ResultType, FinalEnvironment, ContextOut).

% Process one sequence element, returning its type and the environment to
% use for the rest of the sequence.
infer_sequence_item(type_declaration_node(_, _, _, _, _), _Level, _InsideFunction,
                    Environment, _TypeEnvironment, Context, record_type([], closed), Environment, Context) :- !.
% A MODULE is a genuine record VALUE: its body is its own nested scope (own
% `let`-like sequence, one level deeper, seeded with its own `external`s
% exactly like the top level), and its type is a row built from its PUBLIC
% members only -- private members are simply absent from the row (and, in
% codegen, from the emitted object), so they are inaccessible from outside
% both statically and at runtime.  `opaque` on the module marks its exposed
% type NOMINAL (its own name, unregistered as a module type unless ascribed --
% see the module documentation on why an unascribed opaque module does not
% yet support `.field` access); transparent (the default) exposes the row
% directly, structurally.  An explicit `: ModuleType` ascription overrides
% either: the module's own natural row must `subsume` the module type's
% declared row field-by-field, and the exposed type becomes the module type's
% own (nominal or structural per the MODULE TYPE's own opacity, independent of
% the module's own marker).
%
% `Parameters` (a module's own `<T>`, e.g. `module Stack<T> = {...}`) needs
% every member to agree on the SAME `T` -- unlike a generic FUNCTION's `<A>`,
% which only has ONE body to check, a module has MANY members whose
% annotations all need to see the identical binding, or `push`'s `T` and
% `pop`'s `T` could silently end up as two unrelated types.  This reuses the
% EXACT mechanism an ordinary generic function's own explicit `<A B>` already
% uses (see the `function_node(TypeParameters, ...)` clause above):
% `bind_type_parameters_rigid/8` mints ONE rigid skolem per parameter into a
% SCOPED type environment, which is then threaded through -- unchanged --
% into EVERY member's annotation conversion (`seed_externals`/
% `infer_sequence` below), so they all resolve `T` to the identical skolem
% term.  Afterwards, `substitute_skolems/3` swaps that skolem back to its
% paired FLEXIBLE replacement (minted first, at the shallower `Level1`) in
% whatever becomes the module's exposed type, so `generalize/5` finds it and
% abstracts it into the scheme's quantifier list exactly once -- the same
% "mint the replacement first, in declaration order" trick that keeps a
% generic function's explicit type arguments positional (see `generalize/5`'s
% own doc in types.pl) applies here too, which is what a later `Stack<number>`
% (explicit type application on the module VALUE, see the standalone
% `type_application_node` support) instantiates positionally against.
infer_sequence_item(module_node(Name, Parameters, Opacity, Ascription, Items, _Span),
                    Level, InsideFunction, Environment, TypeEnvironment, ContextIn,
                    ModuleType, EnvironmentOut, ContextOut) :- !,
  normalise_module_items(Items, CleanItems, PublicValueNames),
  Level1 is Level + 1,
  ( Parameters == [] ->
      % The common (non-generic) case: nothing to bind rigidly, so this is
      % exactly the module's ORIGINAL (pre-generic) setup, byte-for-byte --
      % zero behavioural change for every module that doesn't declare `<T>`.
      ScopedTypeEnvironment = TypeEnvironment, SkolemPairs = [], BodyLevel = Level1, Context0 = ContextIn
  ; BodyLevel is Level1 + 1,
    bind_type_parameters_rigid(Parameters, TypeEnvironment, Level1, BodyLevel, ContextIn,
                               ScopedTypeEnvironment, SkolemPairs, Context0)
  ),
  seed_externals(CleanItems, ScopedTypeEnvironment, BodyLevel, Environment, Context0, SeededEnvironment, Context1),
  infer_sequence(CleanItems, BodyLevel, InsideFunction, SeededEnvironment, ScopedTypeEnvironment, Context1,
                _BodyLastType, BodyEnvironment, Context2),
  module_member_row(PublicValueNames, BodyEnvironment, MemberFieldsRaw),
  ( Ascription = some(ModuleTypeExpression) ->
      % The ascription is converted in `ScopedTypeEnvironment` too (not the
      % plain outer one) -- it may itself reference the module's own `T`,
      % e.g. `module Stack<T>: Container<T> = {...}`.
      convert_annotation_type(ModuleTypeExpression, ScopedTypeEnvironment, BodyLevel, Context2, ModuleTypeRaw, Context3),
      % `ModuleTypeRaw` is either a SINGLE module type (`module A: B = {...}`,
      % `type_constructor` if `B` is opaque, `record_type` if transparent) or,
      % when the ascription used `+`, an `intersection_type(Members)` (each
      % Member itself a `type_constructor`/`record_type` the same way).  Either
      % way the module's own row must satisfy EVERY module type named -- for a
      % single module type that's one check; for `B + C` it's one check PER
      % member, all against the SAME module row (see
      % `check_module_satisfies_each/7` below).  The check runs BEFORE the
      % skolem substitution just below, while `T` is still the same rigid
      % skolem on both sides (the module's row and, if the ascription
      % mentioned `T`, the module type's row too) -- substituting first would
      % make them impossible to relate to each other correctly.
      ( ModuleTypeRaw = intersection_type(ModuleTypeMembers) ->
          check_module_satisfies_each(ModuleTypeMembers, MemberFieldsRaw, Name, ScopedTypeEnvironment, BodyLevel, Context3, Context5)
      ; check_module_satisfies_one(ModuleTypeRaw, MemberFieldsRaw, Name, ScopedTypeEnvironment, BodyLevel, Context3, Context5)
      ),
      % NOW swap `T`'s skolem back to its flexible replacement -- in whatever
      % `ModuleTypeRaw` turned out to be (a plain module type reference or
      % an intersection; `substitute_skolems/3` dispatches on shape and
      % recurses into an `intersection_type`'s members the same way it
      % recurses into a `type_constructor`'s arguments, see types.pl).
      substitute_skolems(ModuleTypeRaw, SkolemPairs, ModuleType0)
  ; Opacity == opaque ->
      % An unascribed opaque module's synthetic identity ignores `T`
      % entirely (this is the same pre-existing scope limit noted above: it
      % has nowhere to register a row for `.field` access to look up, with
      % or without a type parameter, so there is nothing extra to get right
      % here for the generic case specifically).
      ModuleType0 = type_constructor(Name, []),
      Context5 = Context2
  ; % Transparent, unascribed: the module's own row IS its type, so `T`
    % needs the same skolem-back-to-flexible swap the ascribed branch does,
    % just applied to the row directly (wrapping/unwrapping a throwaway
    % `record_type` is how `substitute_skolems/3`'s existing per-field
    % recursion is reused here, without needing a new exported helper).
    substitute_skolems(record_type(MemberFieldsRaw, closed), SkolemPairs, record_type(MemberFields, closed)),
    ModuleType0 = record_type(MemberFields, closed),
    Context5 = Context2
  ),
  generalize(ModuleType0, Level, Context5, Scheme, Context6),
  put_assoc(Name, Environment, defined(Scheme), EnvironmentOut),
  ModuleType = ModuleType0,
  ContextOut = Context6.
% An `external` declaration carries no inferable body; its (trusted) type was
% already seeded into the environment before the walk, so there is nothing to
% do here.  Its "value" is unit, like a type declaration.
infer_sequence_item(external_node(_, _, _, _), _Level, _InsideFunction,
                    Environment, _TypeEnvironment, Context, record_type([], closed), Environment, Context) :- !.
% A destructuring definition binds the pattern's variables for the rest of
% the sequence (monomorphically); its value is the matched value's type.
infer_sequence_item(destructuring_node(Pattern, Value, _), Level, InsideFunction,
                    Environment, TypeEnvironment, ContextIn, ValueType, EnvironmentOut, ContextOut) :- !,
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context1),
  type_pattern(Pattern, ValueType, Level, TypeEnvironment, Environment, Context1, EnvironmentOut, ContextOut).
infer_sequence_item(definition_node(identifier_node(Name, _), Annotation, Value, _),
                    Level, InsideFunction, Environment, TypeEnvironment, ContextIn,
                    ValueType, EnvironmentOut, ContextOut) :- !,
  Level1 is Level + 1,
  define_value(Annotation, Value, Level1, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context2),
  tie_forward_knot(Name, Environment, ValueType, Context2, Context3),
  generalize(ValueType, Level, Context3, Scheme, Context4),
  put_assoc(Name, Environment, defined(Scheme), EnvironmentOut),
  ContextOut = Context4.
infer_sequence_item(Expression, Level, InsideFunction, Environment, TypeEnvironment,
                    ContextIn, Type, Environment, ContextOut) :-
  infer(Expression, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, Type, ContextOut).

% If this definition's name was referenced forward (its placeholder is
% already solved), unify the placeholder with the value's type to close the
% recursive loop; otherwise leave the placeholder so the definition can be
% generalised independently.
%
% Every definition in sequence position was pre-bound `forward` by
% `prebind_forward`, so the lookup below can only miss when an EARLIER item in
% the SAME sequence already rebound the name `defined` -- i.e. the name is
% defined twice in one scope.  That is an error the user must see, not a bare
% failure that silently collapses the whole analysis.
tie_forward_knot(Name, Environment, ValueType, ContextIn, ContextOut) :-
  ( get_assoc(Name, Environment, forward(Scheme)) ->
      ( Scheme = type_scheme([], Placeholder) ->
          ( placeholder_referenced(Placeholder, ContextIn) ->
              unify(ValueType, Placeholder, ContextIn, ContextOut)
          ; ContextOut = ContextIn
          )
      ; % A declared polymorphic scheme (fully annotated generic literal): the
        % value was checked against the very annotations recursive uses
        % instantiated, so there is no placeholder to tie.
        ContextOut = ContextIn
      )
  ; throw(analysis_error(duplicate_definition(Name)))
  ).

placeholder_referenced(Placeholder, Context) :-
  resolve_head(Placeholder, Context, Resolved),
  Resolved \= Placeholder.

% ---------------------------------------------------------------------------
% Module bodies
% ---------------------------------------------------------------------------

% A module body follows the same use/public normalisation as a top-level
% program (drop `use`/`use_all`, unwrap `public`, remember which names are
% public) -- duplicated in miniature from analyser.pl's `normalise_items/4`
% rather than shared, since analyser.pl itself depends on this module and a
% shared predicate would be circular.  Nested `type` declarations inside a
% module body are not yet supported (a future extension) and are rejected
% with a clear error rather than silently mishandled.
normalise_module_items([], [], []).
normalise_module_items([use_node(_, _, _) | Rest], CleanItems, PublicNames) :- !,
  normalise_module_items(Rest, CleanItems, PublicNames).
normalise_module_items([use_all_node(_, _) | Rest], CleanItems, PublicNames) :- !,
  normalise_module_items(Rest, CleanItems, PublicNames).
normalise_module_items([public_node(definition_node(identifier_node(Name, NSpan), Annotation, Value, DSpan), _) | Rest],
                      [definition_node(identifier_node(Name, NSpan), Annotation, Value, DSpan) | CleanItems],
                      [Name | PublicNames]) :- !,
  normalise_module_items(Rest, CleanItems, PublicNames).
normalise_module_items([public_node(external_node(Name, Type, Source, ESpan), _) | Rest],
                      [external_node(Name, Type, Source, ESpan) | CleanItems], [Name | PublicNames]) :- !,
  normalise_module_items(Rest, CleanItems, PublicNames).
normalise_module_items([public_node(module_node(Name, Parameters, Opacity, Ascription, Items, MSpan), _) | Rest],
                      [module_node(Name, Parameters, Opacity, Ascription, Items, MSpan) | CleanItems], [Name | PublicNames]) :- !,
  normalise_module_items(Rest, CleanItems, PublicNames).
normalise_module_items([public_node(type_declaration_node(Name, _, _, _, _), _) | _Rest], _, _) :- !,
  throw(analysis_error(module_nested_type_not_supported(Name))).
normalise_module_items([type_declaration_node(Name, _, _, _, _) | _Rest], _, _) :- !,
  throw(analysis_error(module_nested_type_not_supported(Name))).
normalise_module_items([public_node(Other, _) | _], _, _) :- !,
  throw(analysis_error(cannot_export(Other))).
normalise_module_items([Item | Rest], [Item | CleanItems], PublicNames) :-
  normalise_module_items(Rest, CleanItems, PublicNames).

% The module's own natural type: a closed row of its PUBLIC members, each
% keyed by name.  A member individually generalised as `type_scheme(Ids, Body)`
% becomes a `forall_type(Ids, Body)` field -- `forall_type` is a first-class
% monotype that nests anywhere (see types.pl), so a rank-2-polymorphic member
% (e.g. `map: <A B>(...)`) is represented exactly, not flattened away.
module_member_row([], _Environment, []).
module_member_row([MemberName | Names], Environment,
                  [record_field(readonly, label(MemberName), FieldType) | Fields]) :-
  ( get_assoc(MemberName, Environment, defined(type_scheme(Ids, Body))) ->
      ( Ids == [] -> FieldType = Body ; FieldType = forall_type(Ids, Body) )
  ; throw(analysis_error(internal_error))
  ),
  module_member_row(Names, Environment, Fields).

% Check the module's own row satisfies an ascribed module type's declared row,
% field by field: the module's actual member type must be at least as
% general as the module type's declared type -- `subsume/5`, the same
% "actual-as-polymorphic-as-expected" check already used for Rank-N generics,
% instantiating the module's member if it is itself generic and skolemising
% the module type's expectation if IT is generic.
check_module_satisfies([], _MemberFields, _Name, _Level, Context, Context).
check_module_satisfies([record_field(_, label(MemberName), ExpectedType) | Rest], MemberFields, Name, Level,
                       ContextIn, ContextOut) :-
  ( memberchk(record_field(_, label(MemberName), ActualType), MemberFields) ->
      subsume(ActualType, ExpectedType, Level, ContextIn, Context1)
  ; throw(analysis_error(missing_module_type_member(Name, MemberName)))
  ),
  check_module_satisfies(Rest, MemberFields, Name, Level, Context1, ContextOut).

% check_module_satisfies_one(+ModuleType, +MemberFields, +Name, +TypeEnvironment,
%                            +Level, +ContextIn, -ContextOut).
%
% Resolve ONE ascribed module type -- `ModuleType` is whatever
% `convert_annotation_type` produced for it, either a `type_constructor`
% (the module type is `opaque`: nominal, so its row is hidden from ordinary
% unification and has to be looked up explicitly, the same way nominal
% FIELD ACCESS does via `module_type_row_for/7`) or a `record_type` directly
% (the module type is transparent: already its own row, nothing to look up)
% -- to its member row, then delegate to `check_module_satisfies/6` above.
% This is the single-module type case (`module A: B = {...}`) AND, called once
% per member, the building block for the intersection case
% (`module A: B + C = {...}`) right below.
check_module_satisfies_one(ModuleType, MemberFields, Name, TypeEnvironment, Level, ContextIn, ContextOut) :-
  ( ModuleType = type_constructor(ModuleTypeName, ModuleTypeArguments) ->
      module_type_row_for(ModuleTypeName, ModuleTypeArguments, TypeEnvironment, Level, ContextIn, ModuleTypeRow, Context1)
  ; ModuleType = record_type(ModuleTypeRow, _) ->
      Context1 = ContextIn
  ; throw(analysis_error(not_a_module_type_ascription(Name)))
  ),
  check_module_satisfies(ModuleTypeRow, MemberFields, Name, Level, Context1, ContextOut).

% Ascribing to `B + C` means satisfying EACH of B and C independently,
% against the SAME module row -- there is no "merged" row to build and check
% once; `MemberFields` (the module's own row) is passed to every member's
% own `check_module_satisfies_one` call unchanged.  A module missing a
% member of ANY one module type fails here with that module type's own
% `missing_module_type_member`/`type_mismatch`-style error, exactly as it
% would if it were ascribed to that module type alone.
check_module_satisfies_each([], _MemberFields, _Name, _TypeEnvironment, _Level, Context, Context).
check_module_satisfies_each([ModuleType | Rest], MemberFields, Name, TypeEnvironment, Level, ContextIn, ContextOut) :-
  check_module_satisfies_one(ModuleType, MemberFields, Name, TypeEnvironment, Level, ContextIn, Context1),
  check_module_satisfies_each(Rest, MemberFields, Name, TypeEnvironment, Level, Context1, ContextOut).

% ---------------------------------------------------------------------------
% The per-node inference rules
% ---------------------------------------------------------------------------

% Literals: a constant base type, context unchanged.
infer(number_node(_, _), _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, number, Context).
infer(boolean_node(_, _), _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, boolean, Context).

% String literal: the result is `string`, but each interpolated `{ expr }`
% must itself be well-typed, so we still infer through it.
infer(string_node(Parts, _), Level, InsideFunction, Environment, TypeEnvironment, ContextIn, string, ContextOut) :-
  infer_string_parts(Parts, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut).

% Variable: look the name up and instantiate its scheme with fresh
% variables at the current level.  A `forward` binding may only be used
% inside a function body.
infer(identifier_node(Name, _), Level, InsideFunction, Environment, _TypeEnvironment, ContextIn, Type, ContextOut) :-
  ( get_assoc(Name, Environment, Binding) ->
      binding_scheme(Binding, InsideFunction, Name, Scheme),
      instantiate(Scheme, Level, ContextIn, Type, ContextOut)
  ; throw(analysis_error(unbound_variable(Name)))
  ).

% Lambda: each parameter gets a fresh monomorphic variable, constrained by
% its annotation if present; the body is typed with those bound and with
% `InsideFunction = true`.  A return annotation, if present, is unified
% against the inferred body type.
infer(function_node([], Parameters, ReturnAnnotation, Body, _), Level, _InsideFunction,
      Environment, TypeEnvironment, ContextIn,
      function_type(ParameterTypes, BodyType), ContextOut) :- !,
  bind_parameters(Parameters, Level, TypeEnvironment, Environment, ContextIn,
                  ParameterTypes, Environment1, Context1),
  type_function_body(ReturnAnnotation, Body, Level, Environment1, TypeEnvironment, Context1, BodyType, ContextOut).

% Lambda with explicit generics (`<A B>(..)`): each unbounded proper
% parameter is a RIGID skolem while the body is checked -- one level deeper,
% so the escape check confines it -- making the body prove it works for an
% ARBITRARY, DISTINCT type per generic (a body that forces `A = B`, or `A =
% number`, is rejected HERE, at the definition, not at some later call site
% as an inscrutable occurs-check/mismatch).  A bounded parameter is its
% bound; a higher-kinded one stays a fresh variable.  Afterwards the skolems
% are swapped back to the flexible variables paired with them (minted first,
% in declaration order, so the scheme's quantifiers stay positional for
% explicit type arguments), and the type generalises exactly as before.
infer(function_node(TypeParameters, Parameters, ReturnAnnotation, Body, _), Level, _InsideFunction,
      Environment, TypeEnvironment, ContextIn, ResultType, ContextOut) :-
  Level1 is Level + 1,
  bind_type_parameters_rigid(TypeParameters, TypeEnvironment, Level, Level1, ContextIn,
                             TypeEnvironment1, SkolemPairs, Context1),
  bind_parameters(Parameters, Level1, TypeEnvironment1, Environment, Context1,
                  ParameterTypes, Environment1, Context2),
  type_function_body(ReturnAnnotation, Body, Level1, Environment1, TypeEnvironment1, Context2, BodyType, ContextOut),
  fully_resolve(function_type(ParameterTypes, BodyType), ContextOut, ResolvedType),
  substitute_skolems(ResolvedType, SkolemPairs, ResultType).

% Record: infer each member into a field.  A literal is a CLOSED record, so
% its tail is `closed`.  Positional members get sequential `index` keys;
% labeled members get `label` keys.  Labels must be unique.
infer(record_node(Members, _), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, record_type(Fields, Tail), ContextOut) :-
  infer_record_members(Members, 0, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, Fields, SpreadTypes, ContextOut),
  check_unique_labels(Fields, []),
  spread_tail(SpreadTypes, Tail).

% Block: its own lexical scope, behaving like a sequence.
infer(block_node(Expressions, _), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, Type, ContextOut) :-
  infer_sequence(Expressions, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, Type, _FinalEnvironment, ContextOut).

% Member access `target.label` / `target.index`: constrain the target to be
% a record having AT LEAST this field (an open row tail), with any
% mutability.  The open tail is what makes `(p) p.x` row-polymorphic: the
% target need not be a fully known record.
%
% When the target is instead a NOMINAL type (a module or module type value --
% an ordinary tagged union has no fields to access this way, its values are
% inspected only through `match`), its row is looked up regardless of its own
% opacity: opacity governs whether some OTHER, differently-named value may
% substitute for it, not whether ITS OWN values support member access.
infer(access_node(Target, Accessor, _), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, FieldType, ContextOut) :-
  infer(Target, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, TargetType, Context1),
  accessor_key(Accessor, Key),
  resolve_head(TargetType, Context1, ResolvedTarget),
  ( ResolvedTarget = type_constructor(TypeName, TypeArguments) ->
      module_type_row_for(TypeName, TypeArguments, TypeEnvironment, Level, Context1, Fields, ContextOut),
      ( memberchk(record_field(_, Key, FieldType), Fields) ->
          true
      ; throw(analysis_error(unknown_member(TypeName, Key)))
      )
  ; fresh_unification_variable(Context1, Level, FieldType, Context2),
    fresh_unification_variable(Context2, Level, AnyMutability, Context3),
    fresh_unification_variable(Context3, Level, RestTail, Context4),
    unify(TargetType, record_type([record_field(AnyMutability, Key, FieldType)], RestTail), Context4, ContextOut)
  ).

% Member assignment `target.member = value`: like access, but the member's
% mutability is required to be `mutable`, and the value's type must match.
infer(assignment_node(access_node(Target, Accessor, _), Value, _), Level, InsideFunction,
      Environment, TypeEnvironment, ContextIn, ValueType, ContextOut) :-
  infer(Target, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, TargetType, Context1),
  accessor_key(Accessor, Key),
  fresh_unification_variable(Context1, Level, FieldType, Context2),
  fresh_unification_variable(Context2, Level, RestTail, Context3),
  unify(TargetType, record_type([record_field(mutable, Key, FieldType)], RestTail), Context3, Context4),
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, Context4, ValueType, Context5),
  unify(ValueType, FieldType, Context5, ContextOut).

% Match: the scrutinee's type must satisfy every arm's pattern, each guard
% must be boolean, and every arm's result has the match's (shared) type.
% Patterns are type-consistent with the scrutinee -- there are no union
% types, so all arms describe the same scrutinee type.
infer(match_node(Scrutinee, RawArms, _), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, ResultType, ContextOut) :-
  infer(Scrutinee, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ScrutineeType, Context1),
  fresh_unification_variable(Context1, Level, ResultType, Context2),
  % An or-pattern's alternatives must bind the same variables; then we desugar
  % each alternative into its own single-pattern arm, which makes the existing
  % typing (per-alternative body), exhaustiveness and codegen sound for free.
  check_or_pattern_bindings(RawArms),
  desugar_arms(RawArms, Arms),
  infer_match_arms(Arms, ScrutineeType, ResultType, Level, InsideFunction, Environment, TypeEnvironment, Context2, Context3),
  check_exhaustiveness(Arms, ScrutineeType, TypeEnvironment, Context3),
  ContextOut = Context3.

% A destructuring reached in expression position cannot bind anything
% visible, so it just contributes the matched value's type.
infer(destructuring_node(Pattern, Value, _), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, ValueType, ContextOut) :-
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context1),
  type_pattern(Pattern, ValueType, Level, TypeEnvironment, Environment, Context1, _DiscardedEnvironment, ContextOut).

% Explicit TYPE APPLICATION at a call site: `foo<number>(1)` fixes the
% callee's type parameters positionally; a hole (`bar<_ boolean>(..)`) and
% every omitted trailing position stay inferred.  Polymorphism has two shapes
% here: a LET-BOUND name carries a type_scheme, whose quantifier list is
% positional (see generalize/5); any other polymorphic value -- e.g. a rank-N
% annotated parameter -- resolves to a forall_type, whose bound ids are in
% annotation source order.  Supplying more arguments than there are
% quantifiers, or type-applying a monomorphic value, is an error.
infer(type_application_node(Target, TypeArguments, _), Level, InsideFunction, Environment,
      TypeEnvironment, ContextIn, Type, ContextOut) :-
  convert_type_arguments(TypeArguments, TypeEnvironment, Level, ContextIn, Provided, Context1),
  ( Target = identifier_node(Name, _),
    get_assoc(Name, Environment, Binding),
    binding_scheme(Binding, InsideFunction, Name, type_scheme(QuantifiedIds, SchemeBody)),
    QuantifiedIds \== [] ->
      check_type_argument_count(QuantifiedIds, Provided),
      instantiate_positional(type_scheme(QuantifiedIds, SchemeBody), Provided, Level, Context1, Type, ContextOut)
  ; infer(Target, Level, InsideFunction, Environment, TypeEnvironment, Context1, TargetType, Context2),
    resolve_head(TargetType, Context2, Resolved),
    ( Resolved = forall_type(BoundIds, _) ->
        check_type_argument_count(BoundIds, Provided),
        instantiate_forall_positional(Resolved, Provided, Level, Context2, Type, ContextOut)
    ; throw(analysis_error(type_arguments_on_monomorphic_value))
    )
  ).

% Application, with partial application and argument PLACEHOLDERS.  A `_`
% argument is a hole: the call is applied to all positions (holes as fresh
% variables), and the whole expression becomes a function awaiting the holes,
% in order.  With no holes this is ordinary application.
infer(function_call_node(Target, Arguments, _), Level, InsideFunction, Environment,
      TypeEnvironment, ContextIn, ResultType, ContextOut) :-
  infer(Target, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, TargetType, Context1),
  apply_call(TargetType, Arguments, Level, InsideFunction, Environment, TypeEnvironment, Context1, ResultType, ContextOut).

% Conditional: the condition must be boolean and the two branches must agree.
infer(conditional_node(Condition, Then, Else, _), Level, InsideFunction, Environment,
      TypeEnvironment, ContextIn, BranchType, ContextOut) :-
  infer(Condition, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ConditionType, Context1),
  unify(ConditionType, boolean, Context1, Context2),
  infer(Then, Level, InsideFunction, Environment, TypeEnvironment, Context2, BranchType, Context3),
  infer(Else, Level, InsideFunction, Environment, TypeEnvironment, Context3, ElseType, Context4),
  unify(BranchType, ElseType, Context4, ContextOut).

% Unary operator.
infer(unary_node(Operator, Operand, _), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, ResultType, ContextOut) :-
  unary_signature(Operator, Level, OperandType, ResultType),
  infer(Operand, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ActualOperandType, Context1),
  unify(ActualOperandType, OperandType, Context1, ContextOut).

% The pipe `x -> f` IS application -- codegen emits exactly `f(x)` -- so it is
% typed by the same `apply_call/9` a call expression uses.  That instantiates a
% polymorphic callee (a `forall_type`, e.g. a generic `external`) before
% applying, and CHECKS the piped value against the parameter, identically to
% `f(x)`.  Routing pipe through the generic binary rule instead would unify the
% callee against a bare `(A) -> B` monotype, which a forall head never matches.
infer(binary_node(pipe, Left, Right, _), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, ResultType, ContextOut) :- !,
  infer(Right, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, TargetType, Context1),
  apply_call(TargetType, [Left], Level, InsideFunction, Environment, TypeEnvironment, Context1, ResultType, ContextOut).

% Binary operator.
infer(binary_node(Operator, Left, Right, _), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, ResultType, ContextOut) :-
  infer(Left, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, LeftActual, Context1),
  infer(Right, Level, InsideFunction, Environment, TypeEnvironment, Context1, RightActual, Context2),
  binary_signature(Operator, Level, Context2, LeftExpected, RightExpected, ResultType, Context3),
  unify(LeftActual, LeftExpected, Context3, Context4),
  unify(RightActual, RightExpected, Context4, ContextOut).

% A malformed node the lowerer could not recognise (`error_node`, from a syntax
% error).  The batch compiler rejects a program with parse diagnostics BEFORE
% inference, so this is normally unreachable; the clause is here so inference is
% TOTAL -- an `error_node` that ever reaches it THROWS (which the accumulating
% LSP checker records as an `error_at` diagnostic) instead of bare-failing and
% collapsing the whole analysis to a silent `false`.
infer(error_node(Span), _Level, _InsideFunction, _Environment, _TypeEnvironment,
      _Context, _ResultType, _ContextOut) :-
  throw(analysis_error(malformed_syntax(Span))).

% A type declaration reached in expression position carries no value.
infer(type_declaration_node(_, _, _, _, _), _Level, _InsideFunction, _Environment, _TypeEnvironment,
      Context, record_type([], closed), Context).

% A definition reached *outside* a sequence position (e.g. as a function
% argument): it cannot bind anything visible, so it just contributes the
% type of its value (still honouring any annotation on it).
infer(definition_node(_Target, Annotation, Value, _), Level, InsideFunction, Environment,
      TypeEnvironment, ContextIn, ValueType, ContextOut) :-
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context1),
  apply_annotation(Annotation, ValueType, TypeEnvironment, Level, Context1, ContextOut).

% ---------------------------------------------------------------------------
% Reader-macro forms (only reachable while type-checking a MACRO BODY -- see
% `transformation/macro.pl`; macros are erased before a normal program is
% inferred).
% ---------------------------------------------------------------------------

% A quasiquote `` `(Template) `` evaluates (at macro-expansion time) to an
% `Ast` value, so its TYPE is `Ast`.  The quoted `Template` is NOT type-checked
% as runtime code -- it may mention names that exist only in the expanded
% program -- so we do not infer it.  We only descend into it to find UNQUOTES
% and require each spliced sub-expression to itself be an `Ast`.
infer(quote_node(Template, _), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, AstType, ContextOut) :-
  macro_ast_type(AstType),
  check_template_unquotes(Template, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut).

% An unquote reached on its own (not collected by an enclosing quasiquote) is a
% misplaced `~` -- a static error.
infer(unquote_node(_, _), _Level, _InsideFunction, _Environment, _TypeEnvironment, _ContextIn, _Type, _ContextOut) :-
  throw(analysis_error(unquote_outside_quasiquote)).

% The monotype of an `Ast` value.  A nullary nominal type, distinct from every
% other type; `transformation/macro.pl` seeds the type name `Ast` to the same
% constructor so `parseItem`'s result and the macro's declared return agree.
macro_ast_type(type_constructor("Ast", [])).

% Walk a quasiquote template, type-checking every `~e` / `~(e)` against `Ast`
% and leaving all other (template) syntax untouched.  A NESTED quasiquote is
% opaque here (its unquotes belong to its own level) -- tier-1 does not support
% nested-quote splicing.
check_template_unquotes(unquote_node(Expression, _), Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut) :- !,
  infer(Expression, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ExpressionType, Context1),
  macro_ast_type(AstType),
  unify(ExpressionType, AstType, Context1, ContextOut).
check_template_unquotes(quote_node(_, _), _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, Context) :- !.
check_template_unquotes(Template, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut) :-
  compound(Template), !,
  Template =.. [_Functor | Arguments],
  check_template_unquotes_each(Arguments, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut).
check_template_unquotes(_Atomic, _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, Context).

check_template_unquotes_each([], _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, Context).
check_template_unquotes_each([Argument | Arguments], Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut) :-
  check_template_unquotes(Argument, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, Context1),
  check_template_unquotes_each(Arguments, Level, InsideFunction, Environment, TypeEnvironment, Context1, ContextOut).

% ---------------------------------------------------------------------------
% Annotations
% ---------------------------------------------------------------------------

% apply_annotation(+Annotation, +InferredType, +TypeEnvironment, +Level, +ContextIn, -ContextOut).
%
% Unify an explicit annotation (if any) against an inferred type.  The
% annotation is converted to a closed monotype via `type_environment.pl`.
apply_annotation(no_annotation, _InferredType, _TypeEnvironment, _Level, Context, Context).
apply_annotation(type_annotation(TypeExpression), InferredType, TypeEnvironment, Level, ContextIn, ContextOut) :-
  convert_annotation_type(TypeExpression, TypeEnvironment, Level, ContextIn, AnnotatedType, Context1),
  unify(AnnotatedType, InferredType, Context1, ContextOut).

% Convert each explicit type argument of a type application; a hole `_`
% becomes a fresh variable, i.e. that position is inferred like an omitted
% trailing one.
convert_type_arguments([], _TypeEnvironment, _Level, Context, [], Context).
convert_type_arguments([type_hole(_) | Rest], TypeEnvironment, Level, ContextIn, [Fresh | Types], ContextOut) :- !,
  fresh_unification_variable(ContextIn, Level, Fresh, Context1),
  convert_type_arguments(Rest, TypeEnvironment, Level, Context1, Types, ContextOut).
convert_type_arguments([TypeExpression | Rest], TypeEnvironment, Level, ContextIn, [Type | Types], ContextOut) :-
  convert_annotation_type(TypeExpression, TypeEnvironment, Level, ContextIn, Type, Context1),
  convert_type_arguments(Rest, TypeEnvironment, Level, Context1, Types, ContextOut).

check_type_argument_count(Quantifiers, Provided) :-
  length(Quantifiers, Arity),
  length(Provided, Given),
  ( Given =< Arity -> true
  ; throw(analysis_error(too_many_type_arguments(Given, Arity)))
  ).

% ---------------------------------------------------------------------------
% Application: bidirectional, with partial application and placeholders
% ---------------------------------------------------------------------------
%
% Application is where rank-N polymorphism is both INTRODUCED and ELIMINATED,
% so it drives the checking direction.  When the callee's type is known:
%   * a polymorphic callee is INSTANTIATED before it is applied;
%   * each argument is CHECKED against its parameter type (not merely inferred
%     then unified) -- this is what lets a polymorphic argument be passed to a
%     parameter that demands a polytype, with instantiation happening at the
%     right (deeper) level inside the check.
% When the callee's type is still unknown we fall back to synthesising the
% argument types and unifying, exactly as before.

% apply_call(+TargetType, +Arguments, +Level, +InsideFunction, +Environment, +TypeEnvironment, +ContextIn, -ResultType, -ContextOut).
apply_call(TargetType, Arguments, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ResultType, ContextOut) :-
  resolve_head(TargetType, ContextIn, Resolved),
  ( Resolved = forall_type(_, _) ->
      instantiate_forall(Resolved, Level, ContextIn, Opened, Context1),
      apply_call(Opened, Arguments, Level, InsideFunction, Environment, TypeEnvironment, Context1, ResultType, ContextOut)
  ; Resolved = function_type(Parameters, Return) ->
      apply_known(Parameters, Return, Arguments, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ResultType, ContextOut)
  ; % Unknown callee, or a non-function: synthesise argument types and let
    % unify settle it or report a mismatch.
    infer_call_arguments(Arguments, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ArgumentTypes, HoleTypes, Context1),
    fresh_unification_variable(Context1, Level, Result, Context2),
    unify(Resolved, function_type(ArgumentTypes, Result), Context2, Context3),
    section_result(HoleTypes, Result, ResultType),
    ContextOut = Context3
  ).

% Apply a callee whose parameter list is known: exact, partial, or
% over-application.  Holes (`_`) and missing trailing parameters both feed the
% resulting section type via `section_result`.
apply_known(Parameters, Return, Arguments, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ResultType, ContextOut) :-
  length(Parameters, ParameterCount),
  length(Arguments, ArgumentCount),
  ( ArgumentCount =< ParameterCount ->
      length(Used, ArgumentCount),
      append(Used, Remaining, Parameters),
      check_arguments(Arguments, Used, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, HoleTypes, ContextOut),
      ( Remaining = [] ->
          Applied = Return
      ; Applied = function_type(Remaining, Return)
      ),
      section_result(HoleTypes, Applied, ResultType)
  ; length(Used, ParameterCount),
    append(Used, SurplusArguments, Arguments),
    check_arguments(Used, Parameters, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, HoleTypes, Context1),
    apply_call(Return, SurplusArguments, Level, InsideFunction, Environment, TypeEnvironment, Context1, Applied, ContextOut),
    section_result(HoleTypes, Applied, ResultType)
  ).

% Check each argument NODE against the parameter type it fills.  A placeholder
% `_` is a hole: it consumes its parameter but constrains nothing, and that
% parameter's type becomes (in order) part of the resulting section's domain.
check_arguments([], [], _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, [], Context).
check_arguments([placeholder_node(_) | Arguments], [Parameter | Parameters], Level, InsideFunction, Environment, TypeEnvironment,
                ContextIn, [Parameter | HoleTypes], ContextOut) :- !,
  check_arguments(Arguments, Parameters, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, HoleTypes, ContextOut).
check_arguments([Argument | Arguments], [Parameter | Parameters], Level, InsideFunction, Environment, TypeEnvironment,
                ContextIn, HoleTypes, ContextOut) :-
  check_expr(Argument, Parameter, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, Context1),
  check_arguments(Arguments, Parameters, Level, InsideFunction, Environment, TypeEnvironment, Context1, HoleTypes, ContextOut).

% ---------------------------------------------------------------------------
% Bidirectional checking
% ---------------------------------------------------------------------------

% check_expr(+Node, +ExpectedType, +Level, +InsideFunction, +Environment, +TypeEnvironment, +ContextIn, -ContextOut).
%
% Check that `Node` has type `ExpectedType`.  When the expectation is a
% polytype we SKOLEMISE it (one level deeper) and check the node against the
% rigid body -- so `Node` must work for an arbitrary type, and a skolem may not
% escape into the surrounding scope.  Otherwise we synthesise the node's type
% and `subsume` it against the expectation (the rank-N generalisation of a
% plain annotation unify; for first-order types this IS a unify).
check_expr(Node, ExpectedType, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut) :-
  resolve_head(ExpectedType, ContextIn, Expected),
  ( Expected = forall_type(BoundIds, Body) ->
      Level1 is Level + 1,
      skolemize_forall(BoundIds, Body, Level1, ContextIn, SkolemBody, Context1),
      check_expr(Node, SkolemBody, Level1, InsideFunction, Environment, TypeEnvironment, Context1, ContextOut)
  ; infer(Node, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ActualType, Context1),
    subsume(ActualType, Expected, Level, Context1, ContextOut)
  ).

% A value definition with an explicit annotation is CHECKED against it (so a
% polytype annotation skolemises and the value is verified polymorphic); its
% declared type is the annotation.  Without an annotation we just synthesise.
define_value(no_annotation, Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, ContextOut) :-
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, ContextOut).
define_value(type_annotation(TypeExpression), Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, AnnotatedType, ContextOut) :-
  convert_annotation_type(TypeExpression, TypeEnvironment, Level, ContextIn, AnnotatedType, Context1),
  check_expr(Value, AnnotatedType, Level, InsideFunction, Environment, TypeEnvironment, Context1, ContextOut).

% A function body is CHECKED against its return annotation when one is written
% (so a function may return a polymorphic value), else synthesised.  The body
% is always typed with `InsideFunction = true`.
type_function_body(no_annotation, Body, Level, Environment, TypeEnvironment, ContextIn, BodyType, ContextOut) :-
  infer(Body, Level, true, Environment, TypeEnvironment, ContextIn, BodyType, ContextOut).
type_function_body(type_annotation(TypeExpression), Body, Level, Environment, TypeEnvironment, ContextIn, BodyType, ContextOut) :-
  convert_annotation_type(TypeExpression, TypeEnvironment, Level, ContextIn, BodyType, Context1),
  check_expr(Body, BodyType, Level, true, Environment, TypeEnvironment, Context1, ContextOut).

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

% Decide which scheme an identifier's binding yields, enforcing that a
% forward reference is only legal inside a function body.
binding_scheme(defined(Scheme), _InsideFunction, _Name, Scheme).
binding_scheme(forward(Scheme), InsideFunction, Name, Scheme) :-
  ( InsideFunction == true ->
      true
  ; throw(analysis_error(forward_reference_outside_function(Name)))
  ).

% Infer each record member into a `record_field`.  Positional members are
% assigned sequential `index` keys (skipping labeled members, which keep the
% counter unchanged); labeled members get `label` keys.  Mutability is
% recorded as the base type `readonly` / `mutable`.
infer_record_members([], _Index, _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, [], [], Context).
% A spread `..value`: the value must be a record, and its fields are spliced
% in.  We collect its type to use as the new record's tail (see spread_tail).
infer_record_members([spread_member(Value, _) | Members], Index, Level,
                    InsideFunction, Environment, TypeEnvironment, ContextIn,
                    Fields, [SpreadType | SpreadTypes], ContextOut) :-
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, SpreadType, Context1),
  % The spread value must be a record; assert that by unifying it with an
  % open empty record, so spreading a non-record is rejected.
  fresh_unification_variable(Context1, Level, AssertTail, Context2),
  unify(SpreadType, record_type([], AssertTail), Context2, Context3),
  infer_record_members(Members, Index, Level, InsideFunction, Environment, TypeEnvironment, Context3, Fields, SpreadTypes, ContextOut).
infer_record_members([record_member(Mutability, Label, Annotation, Value, _) | Members], Index, Level,
                    InsideFunction, Environment, TypeEnvironment, ContextIn,
                    [record_field(Mutability, Key, ValueType) | Fields], SpreadTypes, ContextOut) :-
  member_key(Label, Index, Key, NextIndex),
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context1),
  apply_annotation(Annotation, ValueType, TypeEnvironment, Level, Context1, Context2),
  infer_record_members(Members, NextIndex, Level, InsideFunction, Environment, TypeEnvironment, Context2, Fields, SpreadTypes, ContextOut).

% The explicit fields are the head of the record; a single spread provides
% the tail (so the result is "these fields, then all of the spread's").  A
% closed record (no spread) has tail `closed`.
spread_tail([], closed).
spread_tail([SpreadType], SpreadType).
spread_tail([_, _ | _], _) :-
  throw(analysis_error(multiple_record_spreads_unsupported)).

% A positional member consumes an index; a labeled member does not.
member_key(positional, Index, index(Index), NextIndex) :-
  NextIndex is Index + 1.
member_key(labeled(Name), Index, label(Name), Index).

% A member access's surface accessor (which carries a span) maps to a field
% key (the internal record-field key, which does not).
accessor_key(label(Name, _), label(Name)).
accessor_key(index(Index, _), index(Index)).

% Reject a record that labels two members with the same name.
check_unique_labels([], _).
check_unique_labels([record_field(_, index(_), _) | Fields], Seen) :-
  check_unique_labels(Fields, Seen).
check_unique_labels([record_field(_, label(Name), _) | Fields], Seen) :-
  ( memberchk(Name, Seen) ->
      throw(analysis_error(duplicate_label(Name)))
  ; check_unique_labels(Fields, [Name | Seen])
  ).

% Collect call-argument types in order; a placeholder `_` contributes a fresh
% variable to BOTH the argument list and the (ordered) hole list.
infer_call_arguments([], _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, [], [], Context).
infer_call_arguments([placeholder_node(_) | Arguments], Level, InsideFunction, Environment, TypeEnvironment,
                     ContextIn, [HoleType | ArgumentTypes], [HoleType | HoleTypes], ContextOut) :- !,
  fresh_unification_variable(ContextIn, Level, HoleType, Context1),
  infer_call_arguments(Arguments, Level, InsideFunction, Environment, TypeEnvironment, Context1, ArgumentTypes, HoleTypes, ContextOut).
infer_call_arguments([Argument | Arguments], Level, InsideFunction, Environment, TypeEnvironment,
                     ContextIn, [ArgumentType | ArgumentTypes], HoleTypes, ContextOut) :-
  infer(Argument, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ArgumentType, Context1),
  infer_call_arguments(Arguments, Level, InsideFunction, Environment, TypeEnvironment, Context1, ArgumentTypes, HoleTypes, ContextOut).

% With no holes the result is the application's; with holes it is a function
% from the hole types (in order) to the application's result.
section_result([], AppliedType, AppliedType).
section_result([HoleType | HoleTypes], AppliedType, function_type([HoleType | HoleTypes], AppliedType)).

% Infer a list of expressions left-to-right, collecting their types.
infer_each([], _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, [], Context).
infer_each([E | Es], Level, InsideFunction, Environment, TypeEnvironment, ContextIn, [T | Ts], ContextOut) :-
  infer(E, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, T, Context1),
  infer_each(Es, Level, InsideFunction, Environment, TypeEnvironment, Context1, Ts, ContextOut).

% Bind lambda parameters: each parameter gets a fresh type, constrained by
% its annotation if present, then its pattern is matched against that type to
% bind the parameter's variables (a plain identifier just binds the whole
% parameter; a record pattern destructures it).
bind_parameters([], _Level, _TypeEnvironment, Environment, Context, [], Environment, Context).
bind_parameters([parameter_node(Pattern, Annotation, _) | Parameters], Level,
                TypeEnvironment, Environment, ContextIn,
                [ParameterType | ParameterTypes], EnvironmentOut, ContextOut) :-
  fresh_unification_variable(ContextIn, Level, ParameterType, Context1),
  apply_annotation(Annotation, ParameterType, TypeEnvironment, Level, Context1, Context2),
  type_pattern(Pattern, ParameterType, Level, TypeEnvironment, Environment, Context2, Environment1, Context3),
  bind_parameters(Parameters, Level, TypeEnvironment, Environment1, Context3,
                  ParameterTypes, EnvironmentOut, ContextOut).

% ---------------------------------------------------------------------------
% Match arms and patterns
% ---------------------------------------------------------------------------

infer_match_arms([], _ScrutineeType, _ResultType, _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, Context).
infer_match_arms([match_arm(Pattern, Guard, Result, _Span) | Arms], ScrutineeType, ResultType, Level,
                 InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut) :-
  type_pattern(Pattern, ScrutineeType, Level, TypeEnvironment, Environment, ContextIn, ArmEnvironment, Context1),
  apply_guard(Guard, Level, InsideFunction, ArmEnvironment, TypeEnvironment, Context1, Context2),
  infer(Result, Level, InsideFunction, ArmEnvironment, TypeEnvironment, Context2, ArmResultType, Context3),
  unify(ArmResultType, ResultType, Context3, Context4),
  infer_match_arms(Arms, ScrutineeType, ResultType, Level, InsideFunction, Environment, TypeEnvironment, Context4, ContextOut).

% A guard, if present, must be boolean and is typed with the arm's bindings
% in scope.
apply_guard(no_guard, _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, Context).
apply_guard(guard(Expression), Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut) :-
  infer(Expression, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, GuardType, Context1),
  unify(GuardType, boolean, Context1, ContextOut).

% Expand each arm's alternative patterns into separate single-pattern arms
% (each `match_arm(Pattern, Guard, Result)`) sharing the guard and result.
desugar_arms([], []).
desugar_arms([match_arm(Patterns, Guard, Result, Span) | Rest], Arms) :-
  desugar_alternatives(Patterns, Guard, Result, Span, ArmsHead),
  desugar_arms(Rest, ArmsTail),
  append(ArmsHead, ArmsTail, Arms).

% Each desugared single-pattern arm keeps the original arm's span, so a later
% error (type mismatch, non-exhaustiveness) can still be located at the arm.
desugar_alternatives([], _Guard, _Result, _Span, []).
desugar_alternatives([Pattern | Patterns], Guard, Result, Span, [match_arm(Pattern, Guard, Result, Span) | Rest]) :-
  desugar_alternatives(Patterns, Guard, Result, Span, Rest).

% Every alternative of an or-pattern must bind exactly the same set of
% variables, so the shared body sees a consistent binding regardless of which
% alternative matched.
check_or_pattern_bindings([]).
check_or_pattern_bindings([match_arm(Patterns, _Guard, _Result, _Span) | Rest]) :-
  ( Patterns = [_] ->
      true
  ; Patterns = [First | Others],
    pattern_variables(First, FirstVariables),
    sort(FirstVariables, FirstSet),
    require_same_bindings(Others, FirstSet)
  ),
  check_or_pattern_bindings(Rest).

require_same_bindings([], _Set).
require_same_bindings([Pattern | Patterns], Set) :-
  pattern_variables(Pattern, Variables),
  sort(Variables, PatternSet),
  ( PatternSet == Set ->
      require_same_bindings(Patterns, Set)
  ; throw(analysis_error(or_pattern_bindings_mismatch))
  ).

% The variables a pattern binds.
pattern_variables(wildcard_pattern(_), []).
pattern_variables(binding_pattern(Name, _), [Name]).
pattern_variables(literal_pattern(_, _), []).
pattern_variables(constructor_pattern(_Name, SubPatterns, _), Variables) :-
  patterns_variables(SubPatterns, Variables).
pattern_variables(record_pattern(Members, _), Variables) :-
  member_patterns_variables(Members, Variables).

patterns_variables([], []).
patterns_variables([Pattern | Patterns], Variables) :-
  pattern_variables(Pattern, Head),
  patterns_variables(Patterns, Tail),
  append(Head, Tail, Variables).

member_patterns_variables([], []).
member_patterns_variables([positional_member_pattern(SubPattern, _) | Members], Variables) :-
  pattern_variables(SubPattern, Head),
  member_patterns_variables(Members, Tail),
  append(Head, Tail, Variables).
member_patterns_variables([labeled_member_pattern(_Name, SubPattern, _) | Members], Variables) :-
  pattern_variables(SubPattern, Head),
  member_patterns_variables(Members, Tail),
  append(Head, Tail, Variables).

% Reject a match on a known tagged union that an unguarded arm doesn't cover.
% (Only checked when the scrutinee resolves to a variant type; guarded arms do
% not count as covering, and a bare wildcard / binding arm is a catch-all.)
check_exhaustiveness(Arms, ScrutineeType, TypeEnvironment, Context) :-
  fully_resolve(ScrutineeType, Context, Resolved),
  ( Resolved = type_constructor(Union, _Arguments),
    union_constructor_names(Union, TypeEnvironment, AllConstructors) ->
      ( has_catch_all(Arms) ->
          true
      ; covered_constructors(Arms, Covered),
        missing_constructors(AllConstructors, Covered, Missing),
        ( Missing == [] ->
            true
        ; throw(analysis_error(non_exhaustive_match(Union, Missing)))
        )
      )
  ; true
  ).

has_catch_all([match_arm(Pattern, no_guard, _Result, _Span) | _]) :-
  ( Pattern = wildcard_pattern(_) ; Pattern = binding_pattern(_, _) ),
  !.
has_catch_all([_ | Arms]) :-
  has_catch_all(Arms).

covered_constructors([], []).
covered_constructors([match_arm(constructor_pattern(Name, _, _), no_guard, _, _) | Arms], [Name | Covered]) :- !,
  covered_constructors(Arms, Covered).
covered_constructors([_ | Arms], Covered) :-
  covered_constructors(Arms, Covered).

missing_constructors([], _Covered, []).
missing_constructors([Name | Names], Covered, Missing) :-
  ( memberchk(Name, Covered) ->
      missing_constructors(Names, Covered, Missing)
  ; Missing = [Name | Rest],
    missing_constructors(Names, Covered, Rest)
  ).

% type_pattern(+Pattern, +ExpectedType, +Level, +TypeEnvironment, +EnvironmentIn, +ContextIn, -EnvironmentOut, -ContextOut).
%
% Constrain `ExpectedType` to match `Pattern`, extending the environment with
% the pattern's bindings (monomorphic).
% A malformed pattern (`error_node`, from a syntax error) throws so pattern
% typing stays TOTAL, mirroring the `infer(error_node, ..)` guard above.
type_pattern(error_node(Span), _ExpectedType, _Level, _TypeEnvironment, _Environment, _Context, _EnvironmentOut, _ContextOut) :-
  throw(analysis_error(malformed_syntax(Span))).
type_pattern(wildcard_pattern(_), _ExpectedType, _Level, _TypeEnvironment, Environment, Context, Environment, Context).
type_pattern(binding_pattern(Name, _), ExpectedType, _Level, _TypeEnvironment, EnvironmentIn, Context, EnvironmentOut, Context) :-
  monomorphic_type_scheme(ExpectedType, Scheme),
  put_assoc(Name, EnvironmentIn, defined(Scheme), EnvironmentOut).
type_pattern(literal_pattern(Node, _), ExpectedType, _Level, _TypeEnvironment, Environment, ContextIn, Environment, ContextOut) :-
  literal_type(Node, LiteralType),
  unify(ExpectedType, LiteralType, ContextIn, ContextOut).
% A constructor pattern: the scrutinee must be the constructor's union type,
% and each sub-pattern matches the corresponding field type.
type_pattern(constructor_pattern(CtorName, SubPatterns, _), ExpectedType, Level, TypeEnvironment, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut) :-
  instantiate_constructor(CtorName, TypeEnvironment, Level, ContextIn, UnionType, FieldTypes, Context1),
  ( same_length(SubPatterns, FieldTypes) ->
      true
  ; throw(analysis_error(constructor_pattern_arity_mismatch(CtorName)))
  ),
  unify(ExpectedType, UnionType, Context1, Context2),
  type_pattern_each(SubPatterns, FieldTypes, Level, TypeEnvironment, EnvironmentIn, Context2, EnvironmentOut, ContextOut).
type_pattern(record_pattern(Members, _), ExpectedType, Level, TypeEnvironment, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut) :-
  type_pattern_members(Members, 0, Level, TypeEnvironment, EnvironmentIn, ContextIn, Fields, EnvironmentOut, Context1),
  unify(ExpectedType, record_type(Fields, closed), Context1, ContextOut).

literal_type(number_node(_, _), number).
literal_type(boolean_node(_, _), boolean).
literal_type(string_node(_, _), string).

% Match a list of sub-patterns against a list of (field) types in order.
type_pattern_each([], [], _Level, _TypeEnvironment, Environment, Context, Environment, Context).
type_pattern_each([Pattern | Patterns], [Type | Types], Level, TypeEnvironment, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut) :-
  type_pattern(Pattern, Type, Level, TypeEnvironment, EnvironmentIn, ContextIn, Environment1, Context1),
  type_pattern_each(Patterns, Types, Level, TypeEnvironment, Environment1, Context1, EnvironmentOut, ContextOut).

% Each member contributes a field (with a fresh, don't-care mutability) whose
% type the sub-pattern is then matched against.  Positional members consume an
% index; labeled members do not.  The pattern record is closed (exact).
type_pattern_members([], _Index, _Level, _TypeEnvironment, Environment, Context, [], Environment, Context).
type_pattern_members([positional_member_pattern(SubPattern, _) | Members], Index, Level, TypeEnvironment, EnvironmentIn, ContextIn,
                     [record_field(Mutability, index(Index), FieldType) | Fields], EnvironmentOut, ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Mutability, Context1),
  fresh_unification_variable(Context1, Level, FieldType, Context2),
  type_pattern(SubPattern, FieldType, Level, TypeEnvironment, EnvironmentIn, Context2, Environment1, Context3),
  Index1 is Index + 1,
  type_pattern_members(Members, Index1, Level, TypeEnvironment, Environment1, Context3, Fields, EnvironmentOut, ContextOut).
type_pattern_members([labeled_member_pattern(Name, SubPattern, _) | Members], Index, Level, TypeEnvironment, EnvironmentIn, ContextIn,
                     [record_field(Mutability, label(Name), FieldType) | Fields], EnvironmentOut, ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Mutability, Context1),
  fresh_unification_variable(Context1, Level, FieldType, Context2),
  type_pattern(SubPattern, FieldType, Level, TypeEnvironment, EnvironmentIn, Context2, Environment1, Context3),
  type_pattern_members(Members, Index, Level, TypeEnvironment, Environment1, Context3, Fields, EnvironmentOut, ContextOut).

% Type-check the interpolated expressions inside a string literal.
infer_string_parts([], _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, Context).
infer_string_parts([string_static_part(_) | Parts], Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut) :-
  infer_string_parts(Parts, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut).
infer_string_parts([string_interpolated_part(Node) | Parts], Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut) :-
  infer(Node, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, _Type, Context1),
  infer_string_parts(Parts, Level, InsideFunction, Environment, TypeEnvironment, Context1, ContextOut).
