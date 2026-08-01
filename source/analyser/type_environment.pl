:- module(type_environment, [
  build_type_environment/3,
  build_type_environment/4,
  build_type_environment/5,
  convert_annotation_type/8,
  bind_type_parameters/6,
  bind_type_parameters_rigid/10,
  declared_function_scheme/8,
  instantiate_constructor/9,
  union_constructor_names/3,
  module_type_row_for/7,
  bound_row_fields/6,
  seed_externals/9
]).

/*  type_environment.pl  --  Declared types, type parameters, and conversion
    of surface type expressions into internal monotypes.

    The `TypeEnvironment` is an assoc from a type name to one of:

        type_declaration_info(Opacity, Parameters, BodyExpression)
            a `type` declaration.  `Parameters` is a list of
            type_parameter(Name, Bound), Bound being `no_bound` or
            `bound(TypeExpression)`.

        type_parameter_binding(MonoType)
            a type parameter currently in scope (from a `type` declaration
            being expanded, or from a function's generics).  It resolves to
            a monotype -- a fresh variable, or the converted bound.

    CONVERSION is context-threading (`convert_type/7`), because it must:
      * mint a fresh ROW VARIABLE for an open record `(.. ..)`, so an open
        annotation is genuinely row-polymorphic and generalises; and
      * ENFORCE bounds by unifying a type argument with its parameter's
        bound (`A<R>` with `type A<T: Bound>` requires `R` to satisfy Bound).

    OPAQUE vs STRUCTURAL is unchanged: an opaque reference becomes a
    `type_constructor`; a transparent one expands its body with the
    parameters bound to the arguments (rejecting alias cycles).
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).

:- use_module(types, [
  empty_context/1,
  fresh_unification_variable/4,
  fresh_bound_id/3,
  fresh_named_bound_id/4,
  fresh_named_bound_id/5,
  record_variable_bound/5,
  unify/4,
  subsume/5,
  generalize/5,
  fully_resolve/3
]).
:- use_module('../unicode', [xid_start/1, xid_continue/1]).

% ---------------------------------------------------------------------------
% Hover observations
% ---------------------------------------------------------------------------
%
% Every type-conversion predicate below threads a HoverIn/HoverOut pair,
% mirroring how `Context` is already threaded throughout -- so a hover
% observation can be recorded at each surface type-expression node's own
% span, right where that node's monotype is already being computed, at zero
% extra derivation cost.  An entry is `raw_hover_entry(Span, Kind, Type)`,
% where `Type` is NOT YET fully resolved (it may still contain unification
% variables that only get solved later, elsewhere in the same analysis) --
% resolving happens once, in one pass, against the FINAL context, either at
% the end of the whole file's analysis (see `analyser.pl`'s
% `analyse_accumulating/7`, for annotations reached from real inference) or
% at the end of one declaration's own throwaway validation context (see
% `validate_declarations/3` below, for annotations that live only inside a
% `type` declaration's own body/bounds, which are never threaded into the
% main analysis).  A caller with nothing useful to record (a throwaway
% well-formedness check whose result is discarded anyway) passes a SCRATCH
% pair (`[]`/`_`) instead of threading its own.
hover_note(Span, Kind, Type, HoverIn, [raw_hover_entry(Span, Kind, Type) | HoverIn]).

% ---------------------------------------------------------------------------
% Building the environment
% ---------------------------------------------------------------------------

% build_type_environment(+ProgramNode, -TypeEnvironment, -ConstructorBindings).
%
% `TypeEnvironment` maps type names to their info and variant constructor
% names to `variant_constructor(...)`.  `ConstructorBindings` is a list of
% `CtorName - Scheme` term bindings (each constructor as a function/value),
% to seed the term environment so constructors can be used in expressions.
build_type_environment(ProgramNode, TypeEnvironment, ConstructorBindings) :-
  empty_assoc(Empty),
  build_type_environment(ProgramNode, Empty, TypeEnvironment, ConstructorBindings, _HoverEntries).

% build_type_environment(+ProgramNode, +InitialEnvironment, -TypeEnvironment, -ConstructorBindings).
%
% As above, but starts from `InitialEnvironment` instead of an empty assoc, so
% imported types and constructors (seeded by the module loader) are in scope
% while this module's own declarations are registered and validated.  A local
% declaration that collides with an imported name is rejected as a duplicate.
build_type_environment(program_node(Expressions), InitialEnvironment, TypeEnvironment, ConstructorBindings) :-
  build_type_environment(program_node(Expressions), InitialEnvironment, TypeEnvironment, ConstructorBindings, _HoverEntries).

% build_type_environment/5: like build_type_environment/4, but also returns
% the hover entries recorded while validating each `type` declaration's own
% body/bounds (see `validate_declarations/3`) -- this is the ONLY place those
% annotations are ever converted, so it is also the only place hover for them
% can come from; everywhere else in the file threads its OWN observations
% through the live analysis context instead (see `hover_note/5`'s doc above).
build_type_environment(program_node(Expressions), InitialEnvironment, TypeEnvironment, ConstructorBindings, HoverEntries) :-
  collect_declarations(Expressions, Declarations),
  register_declarations(Declarations, InitialEnvironment, TypeEnvironment),
  validate_declarations(Declarations, TypeEnvironment, HoverEntries),
  build_constructor_bindings(Declarations, TypeEnvironment, ConstructorBindings).

collect_declarations([], []).
collect_declarations([type_declaration_node(Name, Parameters, Opacity, Body, Span) | Rest],
                     [type_declaration_node(Name, Parameters, Opacity, Body, Span) | Declarations]) :- !,
  collect_declarations(Rest, Declarations).
collect_declarations([_ | Rest], Declarations) :-
  collect_declarations(Rest, Declarations).

register_declarations([], Environment, Environment).
% A tagged-union declaration: register the (nominal) type AND each of its
% constructors (so they can be looked up for construction and matching).
register_declarations([type_declaration_node(Name, Parameters, _Opacity, variant_body(Constructors), _) | Rest],
                      EnvironmentIn, EnvironmentOut) :- !,
  register_type_name(Name, Parameters, EnvironmentIn),
  put_assoc(Name, EnvironmentIn, type_variant_info(Parameters, Constructors), Environment1),
  register_constructors(Constructors, Name, Parameters, Environment1, Environment2),
  register_declarations(Rest, Environment2, EnvironmentOut).
% A module type (module-type) declaration: registered distinctly from a plain
% alias so `convert_named/10` can give it its own opaque(nominal)/transparent
% (structural row) semantics.
register_declarations([type_declaration_node(Name, Parameters, Opacity, module_type_body(Members), _) | Rest],
                      EnvironmentIn, EnvironmentOut) :- !,
  register_type_name(Name, Parameters, EnvironmentIn),
  put_assoc(Name, EnvironmentIn, type_module_type_info(Opacity, Parameters, Members), Environment1),
  register_declarations(Rest, Environment1, EnvironmentOut).
register_declarations([type_declaration_node(Name, Parameters, Opacity, Body, _) | Rest],
                      EnvironmentIn, EnvironmentOut) :-
  register_type_name(Name, Parameters, EnvironmentIn),
  put_assoc(Name, EnvironmentIn, type_declaration_info(Opacity, Parameters, Body), Environment1),
  register_declarations(Rest, Environment1, EnvironmentOut).

register_type_name(Name, Parameters, Environment) :-
  ( get_assoc(Name, Environment, _) ->
      throw(analysis_error(duplicate_type_declaration(Name)))
  ; true
  ),
  parameter_names(Parameters, ParameterNames),
  ( has_duplicate(ParameterNames) ->
      throw(analysis_error(duplicate_type_parameter(Name)))
  ; true
  ).

% Constructors live under a distinct `constructor_key/1` namespace, so a
% constructor may share its type's name (e.g. `type Box = Box(number)`).
register_constructors([], _Union, _Parameters, Environment, Environment).
register_constructors([constructor(CtorName, FieldTypes, _) | Rest], Union, Parameters,
                      EnvironmentIn, EnvironmentOut) :-
  ( get_assoc(constructor_key(CtorName), EnvironmentIn, _) ->
      throw(analysis_error(duplicate_constructor(CtorName)))
  ; true
  ),
  put_assoc(constructor_key(CtorName), EnvironmentIn, variant_constructor(Union, Parameters, FieldTypes), Environment1),
  register_constructors(Rest, Union, Parameters, Environment1, EnvironmentOut).

% validate_declarations(+Declarations, +TypeEnvironment, -HoverEntries).
%
% Validate each declaration's bounds and body in a throwaway context (the
% fresh variables it mints are discarded).  Marking the declaration's own
% name as being expanded catches structural self-cycles.
%
% This is also the ONLY place a `type` declaration's OWN body/bounds are ever
% converted with a span worth recording for hover (real inference never
% revisits a declaration's surface syntax -- it only reads the ALREADY-
% converted `TypeEnvironment` entry).  Because each declaration validates in
% its OWN fresh, throwaway `Context` (a separate unification-variable id
% space from every other declaration and from the main analysis), its raw
% hover entries must be resolved HERE, against THIS declaration's own final
% context, before that context is discarded -- deferring them to some later,
% unrelated context would resolve them against the wrong id space entirely.
validate_declarations([], _, []).
% A tagged-union declaration's OWN name shows its constructors, quantified
% over its own type parameters (`<A> Some(A) | None`) -- unlike a
% parametrised record ALIAS (see the plain-alias clause below, which
% deliberately excludes that case), a parametrised variant's name has a
% perfectly good single rendering: a generic FUNCTION's own name already
% renders `<A>(A): A` the same way (see `named_generic_function`/hover.pl),
% so there is nothing alias-shaped (no ambiguous "which instantiation?"
% question) standing in the way here.
validate_declarations([type_declaration_node(_Name, Parameters, _Opacity, variant_body(Constructors), Span) | Rest],
                      TypeEnvironment, HoverEntries) :- !,
  empty_context(Context0),
  bind_validation_parameters(Parameters, TypeEnvironment, Context0, ValidationEnvironment, Context1),
  validate_constructor_fields(Constructors, ValidationEnvironment, Context1, [], RawHover, CtorDisplays, FinalContext),
  finalize_hover_entries(RawHover, FinalContext, TheseEntries0),
  variant_declaration_hover_entry(Parameters, ValidationEnvironment, CtorDisplays, FinalContext, Span, DeclEntry),
  TheseEntries = [DeclEntry | TheseEntries0],
  validate_declarations(Rest, TypeEnvironment, RestEntries),
  append(TheseEntries, RestEntries, HoverEntries).
% A bodyless (abstract FFI) declaration has no body to validate; its parameter
% bounds are still checked.
validate_declarations([type_declaration_node(_Name, Parameters, _Opacity, no_body, _) | Rest],
                      TypeEnvironment, HoverEntries) :- !,
  empty_context(Context0),
  bind_validation_parameters(Parameters, TypeEnvironment, Context0, _ValidationEnvironment, _Context1),
  validate_declarations(Rest, TypeEnvironment, HoverEntries).
% A module type's members are each validated as an ordinary proper type; also
% builds their row via `convert_module_type_members/9` (the SAME helper a use
% site's `convert_named/10` calls for a transparent module type) so a
% non-parametrised declaration's own name can show `{tag: number}` on hover
% too, regardless of its own opacity marker -- opacity governs what an
% OUTSIDE value may substitute for, not what the declaration's own author
% sees hovering their own source.
validate_declarations([type_declaration_node(Name, Parameters, _Opacity, module_type_body(Members), Span) | Rest],
                      TypeEnvironment, HoverEntries) :- !,
  empty_context(Context0),
  bind_validation_parameters(Parameters, TypeEnvironment, Context0, ValidationEnvironment, Context1),
  convert_module_type_members(Members, ValidationEnvironment, [Name], 0, Context1, Fields, FinalContext, [], RawHover),
  ( Parameters == [] ->
      % Store as an ordinary `record_type` while raw -- `fully_resolve/3` (see
      % types.pl) has no clause for `module_row/2`, so resolving it directly
      % would leave any unification variable still inside `Fields` UNCHASED.
      % Swap to `module_row/2` (braces, not parens -- see diagnostics.pl's
      % `tt/3` doc) only AFTER `finalize_hover_entries/3` below has fully
      % resolved it; this Type only ever reaches hover display, never
      % inference, so there is no unification-side meaning lost by the swap.
      hover_note(Span, declaration, record_type(Fields, closed), RawHover, RawHover1),
      finalize_hover_entries(RawHover1, FinalContext, [hover_entry(Span, declaration, semantic(Resolved, Names)) | OtherEntries]),
      ( Resolved = record_type(ResolvedFields, ResolvedTail) -> Display = module_row(ResolvedFields, ResolvedTail) ; Display = Resolved ),
      TheseEntries = [hover_entry(Span, declaration, semantic(Display, Names)) | OtherEntries]
  ; finalize_hover_entries(RawHover, FinalContext, TheseEntries)
  ),
  validate_declarations(Rest, TypeEnvironment, RestEntries),
  append(TheseEntries, RestEntries, HoverEntries).
validate_declarations([type_declaration_node(Name, Parameters, _Opacity, Body, Span) | Rest],
                      TypeEnvironment, HoverEntries) :-
  empty_context(Context0),
  bind_validation_parameters(Parameters, TypeEnvironment, Context0, ValidationEnvironment, Context1),
  % The body may be higher-kinded (an alias bound to a SECTION), so do not
  % force kind 0 here; a higher-kinded alias used in a proper position is
  % rejected at the USE site by `convert_proper`.
  convert_type(Body, ValidationEnvironment, [Name], 0, Context1, Validated, _Kind, FinalContext, [], RawHover),
  % The declaration's OWN name (`type Named = ..`'s `Named`) shows the alias's
  % resolved body (`{tag: number}`), not just the generic identifier syntax
  % help -- but only for a NON-parametrised alias: a parameter (`type Box<T> =
  % ..`) binds validation-only placeholders in `ValidationEnvironment` that
  % have no meaningful monomorphic rendering here, so `Box`'s own name is left
  % to the generic syntax fallback, same as a variant/module-type/abstract
  % declaration's name already is below.
  ( Parameters == [] -> hover_note(Span, declaration, Validated, RawHover, RawHover1) ; RawHover1 = RawHover ),
  finalize_hover_entries(RawHover1, FinalContext, TheseEntries),
  validate_declarations(Rest, TypeEnvironment, RestEntries),
  append(TheseEntries, RestEntries, HoverEntries).

% finalize_hover_entries(+RawEntries, +Context, -HoverEntries).
%
% Resolve every raw entry recorded during ONE throwaway validation context
% against that SAME context's final substitutions, turning each into a
% ready-to-render `hover_entry(Span, Kind, semantic(ResolvedType, none))` --
% see `hover_note/5`'s doc for why this must happen locally, per-context,
% rather than being deferred to some other, unrelated final context.
finalize_hover_entries([], _Context, []).
finalize_hover_entries([raw_hover_entry(Span, Kind, Type) | Rest], Context, [hover_entry(Span, Kind, semantic(Resolved, none)) | Entries]) :-
  fully_resolve(Type, Context, Resolved),
  finalize_hover_entries(Rest, Context, Entries).

% Also collects each constructor's own NAME paired with its converted field
% types (`CtorDisplays`) -- needed so the declaration's OWN name can hover as
% `Ctor(t ..) | Ctor2 | ..` (see `validate_declarations/3`'s variant_body
% clause); every other caller of the ORIGINAL 6-arg form no longer exists (its
% one call site now wants the displays too), so there is no reason to keep
% both.
validate_constructor_fields([], _Environment, Context, Hover, Hover, [], Context).
validate_constructor_fields([constructor(Name, FieldTypes, _) | Rest], Environment, ContextIn, HoverIn, HoverOut,
                           [ctor_display(Name, ConvertedFields) | CtorDisplays], ContextOut) :-
  convert_field_types(FieldTypes, Environment, 0, ContextIn, ConvertedFields, Context1, HoverIn, Hover1),
  validate_constructor_fields(Rest, Environment, Context1, Hover1, HoverOut, CtorDisplays, ContextOut).

% variant_declaration_hover_entry(+Parameters, +ValidationEnvironment, +CtorDisplays,
%                                 +FinalContext, +Span, -DeclEntry).
%
% Builds the variant declaration's OWN name's hover entry: `<A> Some(A) |
% None`, or bare `Some(A) | None` when `Parameters == []`. Unlike every OTHER
% raw hover entry in this file, this is NOT threaded through `hover_note/5` +
% `finalize_hover_entries/3` -- it is assembled directly, here, from data
% already resolved against `FinalContext` (the SAME context every other entry
% in this clause resolves against), so there is nothing left to defer.
%
% Each parameter was bound (by `bind_validation_parameters/5`) to a fresh
% unification variable at level 0, purely so `convert_proper` had something
% to look `A` up to while validating the constructors' fields -- so it now
% shows up INSIDE `CtorDisplays` as an ordinary `unification_variable(Id)`,
% indistinguishable from a real inference variable. `promote_parameters/3`
% below rewrites exactly those known ids (and only those -- anything else
% stays `unification_variable(_)`, same as if this were a normal, unrelated
% type) to `quantified_variable(Id)`, the form `tt/3`'s existing
% `forall_type`/`NamesTable` rendering already knows how to print by name.
variant_declaration_hover_entry(Parameters, ValidationEnvironment, CtorDisplays, FinalContext, Span,
                                hover_entry(Span, declaration, semantic(DisplayType, NamesTable))) :-
  parameter_ids(Parameters, ValidationEnvironment, ParamIdPairs),
  pair_seconds(ParamIdPairs, ParamIds),
  resolve_and_promote_ctors(CtorDisplays, ParamIds, FinalContext, DisplayCtors),
  ( ParamIds == [] ->
      DisplayType = variant_type(DisplayCtors), NamesTable = none
  ; DisplayType = forall_type(ParamIds, variant_type(DisplayCtors)),
    parameter_names_table(ParamIdPairs, NamesTable)
  ).

% Each `type_parameter(Name, _, _, _)` was bound (by `bind_validation_
% parameters/5`, already run over the SAME `Parameters` list) to a
% `type_parameter_binding(unification_variable(Id), _)` under its own Name in
% `ValidationEnvironment` -- looked back up here, by name, rather than
% re-minted, so this refers to the EXACT SAME id `CtorDisplays` already
% contains.
parameter_ids([], _ValidationEnvironment, []).
parameter_ids([type_parameter(Name, _Kind, _Bound, _) | Rest], ValidationEnvironment, [Name - Id | Ids]) :-
  get_assoc(Name, ValidationEnvironment, type_parameter_binding(unification_variable(Id), _)),
  parameter_ids(Rest, ValidationEnvironment, Ids).

pair_seconds([], []).
pair_seconds([_ - V | Rest], [V | Vs]) :- pair_seconds(Rest, Vs).

parameter_names_table([], []).
parameter_names_table([Name - Id | Rest], [Id - Name - no_bound | Names]) :-
  parameter_names_table(Rest, Names).

resolve_and_promote_ctors([], _ParamIds, _Context, []).
resolve_and_promote_ctors([ctor_display(Name, Fields) | Rest], ParamIds, Context, [ctor_display(Name, DisplayFields) | DisplayRest]) :-
  resolve_and_promote_list(Fields, ParamIds, Context, DisplayFields),
  resolve_and_promote_ctors(Rest, ParamIds, Context, DisplayRest).

resolve_and_promote_list([], _ParamIds, _Context, []).
resolve_and_promote_list([Type | Types], ParamIds, Context, [Display | Displays]) :-
  fully_resolve(Type, Context, Resolved),
  promote_parameters(Resolved, ParamIds, Display),
  resolve_and_promote_list(Types, ParamIds, Context, Displays).

% promote_parameters(+Type, +ParamIds, -Display): structural copy of a fully-
% resolved type, rewriting a `unification_variable(Id)` to `quantified_
% variable(Id)` exactly when `Id` is one of THIS declaration's own type
% parameters -- everything else (an unrelated variable, a base type, a
% skolem, an already-quantified variable) passes through unchanged. Mirrors
% `fully_resolve/3`'s own structural dispatch (types.pl), since a parameter
% may appear nested inside a field's function/record/nominal type, not just
% bare.
promote_parameters(unification_variable(Id), ParamIds, quantified_variable(Id)) :- memberchk(Id, ParamIds), !.
promote_parameters(function_type(Params, Return), ParamIds, function_type(Params1, Return1)) :- !,
  resolve_and_promote_list_bare(Params, ParamIds, Params1),
  promote_parameters(Return, ParamIds, Return1).
promote_parameters(record_type(Fields, Tail), ParamIds, record_type(Fields1, Tail)) :- !,
  promote_parameter_fields(Fields, ParamIds, Fields1).
promote_parameters(type_constructor(Name, Args), ParamIds, type_constructor(Name, Args1)) :- !,
  resolve_and_promote_list_bare(Args, ParamIds, Args1).
promote_parameters(forall_type(Ids, Body), ParamIds, forall_type(Ids, Body1)) :- !,
  promote_parameters(Body, ParamIds, Body1).
promote_parameters(intersection_type(Members), ParamIds, intersection_type(Members1)) :- !,
  resolve_and_promote_list_bare(Members, ParamIds, Members1).
promote_parameters(Type, _ParamIds, Type).

% Like `resolve_and_promote_list/4`, but the type is already fully resolved
% (a SUB-term of one that was) -- no context to resolve against again.
resolve_and_promote_list_bare([], _ParamIds, []).
resolve_and_promote_list_bare([Type | Types], ParamIds, [Display | Displays]) :-
  promote_parameters(Type, ParamIds, Display),
  resolve_and_promote_list_bare(Types, ParamIds, Displays).

promote_parameter_fields([], _ParamIds, []).
promote_parameter_fields([record_field(Mutability, Key, Type) | Fields], ParamIds, [record_field(Mutability, Key, Display) | Displays]) :-
  promote_parameters(Type, ParamIds, Display),
  promote_parameter_fields(Fields, ParamIds, Displays).

% Convert a constructor's positional field type expressions (each proper).
convert_field_types([], _Environment, _Level, Context, [], Context, Hover, Hover).
convert_field_types([FieldExpression | Rest], Environment, Level, ContextIn, [FieldType | FieldTypes], ContextOut, HoverIn, HoverOut) :-
  convert_proper(FieldExpression, Environment, [], Level, ContextIn, FieldType, Context1, HoverIn, Hover1),
  convert_field_types(Rest, Environment, Level, Context1, FieldTypes, ContextOut, Hover1, HoverOut).

% ---------------------------------------------------------------------------
% Constructors as values, and constructor instantiation for patterns
% ---------------------------------------------------------------------------

% Build a term binding (a type scheme) for every variant constructor.  A
% constructor `C(t1 .. tn)` of `type U<p1 .. pk> = ...` gets the scheme
% forall p1..pk. (t1 .. tn) -> U<p1 .. pk>; a nullary constructor is just a
% value of type U<p1 .. pk>.
build_constructor_bindings([], _TypeEnvironment, []).
build_constructor_bindings([type_declaration_node(Name, Parameters, _Opacity, variant_body(Constructors), _) | Rest],
                           TypeEnvironment, Bindings) :- !,
  constructor_schemes(Constructors, Name, Parameters, TypeEnvironment, ThisBindings),
  build_constructor_bindings(Rest, TypeEnvironment, RestBindings),
  append(ThisBindings, RestBindings, Bindings).
build_constructor_bindings([_ | Rest], TypeEnvironment, Bindings) :-
  build_constructor_bindings(Rest, TypeEnvironment, Bindings).

constructor_schemes([], _Union, _Parameters, _TypeEnvironment, []).
constructor_schemes([constructor(CtorName, FieldExpressions, _) | Rest], Union, Parameters, TypeEnvironment,
                    [CtorName - Scheme | Schemes]) :-
  constructor_scheme(Union, Parameters, FieldExpressions, TypeEnvironment, Scheme),
  constructor_schemes(Rest, Union, Parameters, TypeEnvironment, Schemes).

constructor_scheme(Union, Parameters, FieldExpressions, TypeEnvironment, type_scheme(QuantifiedIds, Body)) :-
  quantified_parameter_scope(Parameters, 0, TypeEnvironment, ScopeEnvironment, QuantifiedVariables, QuantifiedIds),
  empty_context(Context0),
  % Scratch hover pair: this scheme-building pass shares its throwaway
  % context with nothing else, and a constructor's field-type hover already
  % comes from `validate_constructor_fields`'s pass over the SAME source
  % nodes (see `validate_declarations/3`), so there is nothing new to record.
  convert_field_types(FieldExpressions, ScopeEnvironment, 0, Context0, FieldTypes, _Context1, [], _),
  Result = type_constructor(Union, QuantifiedVariables),
  ( FieldTypes == [] ->
      Body = Result
  ; Body = function_type(FieldTypes, Result)
  ).

% Bind each parameter to `quantified_variable(Index)` (the scheme's bound
% variables) and collect those variables and their ids.
quantified_parameter_scope([], _Index, Environment, Environment, [], []).
quantified_parameter_scope([type_parameter(Name, Kind, _Bound, _) | Rest], Index, EnvironmentIn, EnvironmentOut,
                           [quantified_variable(Index) | Variables], [Index | Ids]) :-
  put_assoc(Name, EnvironmentIn, type_parameter_binding(quantified_variable(Index), Kind), Environment1),
  Index1 is Index + 1,
  quantified_parameter_scope(Rest, Index1, Environment1, EnvironmentOut, Variables, Ids).

% instantiate_constructor(+CtorName, +TypeEnvironment, +Level, +ContextIn, -UnionType, -FieldTypes, -ContextOut, +HoverIn, -HoverOut).
%
% For pattern matching: produce the constructor's union type and field types
% with the union's parameters freshly instantiated at `Level`.  Threads a
% REAL hover accumulator (unlike `constructor_scheme`'s scratch pair above):
% this runs in the live analysis context, at a constructor PATTERN's own use
% site, so its raw field-type entries defer to the whole file's final
% resolution exactly like any other annotation reached from inference (see
% `analyser.pl`'s `analyse_accumulating/7`) -- even though the recorded span
% is still the DECLARATION's field-type node (there is no separate span for
% "this field, as destructured by this particular pattern"), the caller
% (`infer.pl`'s `type_pattern/8`) is what records entries at the PATTERN's
% OWN sub-binding spans, using these FieldTypes positionally.
instantiate_constructor(CtorName, TypeEnvironment, Level, ContextIn, UnionType, FieldTypes, ContextOut, HoverIn, HoverOut) :-
  ( get_assoc(constructor_key(CtorName), TypeEnvironment, variant_constructor(Union, Parameters, FieldExpressions)) ->
      fresh_parameter_scope(Parameters, TypeEnvironment, Level, ContextIn, ScopeEnvironment, FreshVariables, Context1),
      UnionType = type_constructor(Union, FreshVariables),
      convert_field_types(FieldExpressions, ScopeEnvironment, Level, Context1, FieldTypes, ContextOut, HoverIn, HoverOut)
  ; throw(analysis_error(unknown_constructor(CtorName)))
  ).

fresh_parameter_scope([], Environment, _Level, Context, Environment, [], Context).
fresh_parameter_scope([type_parameter(Name, Kind, _Bound, _) | Rest], EnvironmentIn, Level, ContextIn,
                      EnvironmentOut, [Fresh | Variables], ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Fresh, Context1),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(Fresh, Kind), Environment1),
  fresh_parameter_scope(Rest, Environment1, Level, Context1, EnvironmentOut, Variables, ContextOut).

% union_constructor_names(+UnionName, +TypeEnvironment, -Names).
union_constructor_names(UnionName, TypeEnvironment, Names) :-
  get_assoc(UnionName, TypeEnvironment, type_variant_info(_Parameters, Constructors)),
  findall(Name, member(constructor(Name, _Fields, _), Constructors), Names).

% Bind each parameter to a fresh placeholder for validation, after checking
% its bound is itself well-formed.  Scratch hover pair for `validate_bound`:
% this is a WELL-FORMEDNESS check in a throwaway context whose result is
% discarded (`_BoundType`), not the real binding site for the parameter (see
% `bind_quantifier_parameters`/`bind_type_parameters_rigid` for those), so
% there is nothing here worth recording.
bind_validation_parameters([], Environment, Context, Environment, Context).
bind_validation_parameters([type_parameter(Name, Kind, Bound, _) | Rest], EnvironmentIn, ContextIn,
                           EnvironmentOut, ContextOut) :-
  validate_bound(Bound, EnvironmentIn, ContextIn, _BoundType, Context1, [], _),
  fresh_unification_variable(Context1, 0, Placeholder, Context2),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(Placeholder, Kind), Environment1),
  bind_validation_parameters(Rest, Environment1, Context2, EnvironmentOut, ContextOut).

% validate_bound(+Bound, +Environment, +ContextIn, -BoundType, -ContextOut, +HoverIn, -HoverOut).
%
% `BoundType` is `no_bound`, or the bound expression converted to a monotype
% -- returned (not discarded) so `bind_quantifier_parameters/8` can stash it
% against the parameter's id for hover to render later (see
% `fresh_named_bound_id/5`).
validate_bound(no_bound, _Environment, Context, no_bound, Context, Hover, Hover).
validate_bound(bound(BoundExpression), Environment, ContextIn, BoundType, ContextOut, HoverIn, HoverOut) :-
  convert_proper(BoundExpression, Environment, [], 0, ContextIn, BoundType, ContextOut, HoverIn, HoverOut).

% Bind a quantified type's parameters: each becomes a fresh, globally-unique
% `quantified_variable` (so it is BOUND in the resulting `forall_type` body),
% carrying its declared kind.  A bound, if written, is checked well-formed (a
% later parameter's bound may mention an earlier one), as in declarations.
% Also records a `type_parameter` hover entry at the parameter's own span
% (see `bind_type_parameters_rigid`'s matching entry for the function/module-
% generic case, and its doc for why a bare `quantified_variable(Id)` is the
% right raw payload here too).
bind_quantifier_parameters([], Environment, Context, Environment, [], Context, Hover, Hover).
bind_quantifier_parameters([type_parameter(Name, Kind, Bound, Span) | Rest], EnvironmentIn, ContextIn,
                           EnvironmentOut, [Id | Ids], ContextOut, HoverIn, HoverOut) :-
  validate_bound(Bound, EnvironmentIn, ContextIn, BoundType, Context1, HoverIn, Hover1),
  fresh_named_bound_id(Context1, Name, BoundType, Id, Context2),
  hover_note(Span, type_parameter, quantified_variable(Id), Hover1, Hover2),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(quantified_variable(Id), Kind), Environment1),
  bind_quantifier_parameters(Rest, Environment1, Context2, EnvironmentOut, Ids, ContextOut, Hover2, HoverOut).

% ---------------------------------------------------------------------------
% Binding function/anonymous type parameters into an environment
% ---------------------------------------------------------------------------

% bind_type_parameters(+TypeParameters, +EnvironmentIn, +Level, +ContextIn, -EnvironmentOut, -ContextOut).
%
% Extend an environment with a function's generics.  An unbounded parameter
% becomes a fresh type variable; a bounded one becomes its converted bound
% (e.g. an open record), so references to the parameter carry the bound.
% A later parameter's bound may mention an earlier one.
bind_type_parameters([], Environment, _Level, Context, Environment, Context).
bind_type_parameters([type_parameter(Name, Kind, Bound, _) | Rest], EnvironmentIn, Level, ContextIn,
                     EnvironmentOut, ContextOut) :-
  parameter_monotype(Kind, Bound, EnvironmentIn, Level, ContextIn, MonoType, Context1),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(MonoType, Kind), Environment1),
  bind_type_parameters(Rest, Environment1, Level, Context1, EnvironmentOut, ContextOut).

% declared_function_scheme(+ValueNode, +TypeEnvironment, +Level, +ContextIn, -Scheme, -ContextOut).
%
% The polymorphic scheme DECLARED by a generic function literal whose
% parameters and return type are all annotated: the type parameters become
% the scheme's quantifiers and the annotations its body.  Used to pre-bind a
% definition's forward placeholder, so a recursive use instantiates the
% declared signature polymorphically instead of leaking the body's rigid
% skolems into an outer-level placeholder.  Fails when the value is not a
% fully annotated generic function literal.
declared_function_scheme(function_node(TypeParameters, Parameters, type_annotation(ReturnExpression), _Body, _Span),
                         TypeEnvironment, Level, ContextIn,
                         type_scheme(BoundIds, function_type(ParameterTypes, ReturnType)), ContextOut,
                         HoverIn, HoverOut) :-
  TypeParameters = [_ | _],
  parameter_annotation_expressions(Parameters, ParameterExpressions),
  bind_quantifier_parameters(TypeParameters, TypeEnvironment, ContextIn, Environment1, BoundIds, Context1, HoverIn, Hover1),
  convert_proper_each(ParameterExpressions, Environment1, [], Level, Context1, ParameterTypes, Context2, Hover1, Hover2),
  convert_proper(ReturnExpression, Environment1, [], Level, Context2, ReturnType, ContextOut, Hover2, HoverOut).

parameter_annotation_expressions([], []).
parameter_annotation_expressions([parameter_node(_, type_annotation(Expression), _) | Rest],
                                 [Expression | Expressions]) :-
  parameter_annotation_expressions(Rest, Expressions).

% bind_type_parameters_rigid(+TypeParameters, +EnvironmentIn, +OuterLevel, +BodyLevel,
%                            +ContextIn, -EnvironmentOut, -SkolemPairs, -ContextOut).
%
% Every PROPER parameter (bounded or not) becomes a RIGID skolem (born at
% BodyLevel, the function body's level), so the body must treat each
% declared generic as an arbitrary, distinct type: collapsing two of them, or
% equating one with a concrete type, is a type error at the definition site
% rather than a silently less-general function.  Each skolem is paired with a
% flexible variable minted FIRST at OuterLevel -- these replace the skolems
% in the function's resulting type (see substitute_skolems), and minting
% them in declaration order before any parameter/body variable keeps the
% generalised scheme's quantifiers positional (see generalize/5).
%
% A BOUND, if written, is converted and attached to BOTH the skolem's id and
% its paired flexible replacement's id (`record_variable_bound/5`): the
% skolem's copy is what lets member access on the parameter reach the
% bound's capabilities WHILE the body is checked (`x.info(..)` for `x: A`,
% `A: Logger` -- see infer.pl's `access_node` clause and `bound_row_fields/6`
% below); the replacement's copy is what survives once the skolem is
% swapped away and the type generalises, so a LATER instantiation (a call
% site, or a further re-generalisation if the value is only referenced, not
% called) still knows to enforce it -- see `any_bound/3`'s use in
% `bind_unification_variable/4` and the instantiation helpers in types.pl.
% This is what makes `<A: Logger + Named>(x: A): A` keep `A`'s identity
% (rather than collapsing it into its bound's structural shape) WITHOUT
% losing the bound-satisfaction check that used to fall out for free from
% that structural substitution.
%
% A higher-kinded parameter (kind > 0) is unaffected: it is always a fresh
% variable, per `parameter_monotype/7`'s own kind>0 clause.
bind_type_parameters_rigid([], Environment, _OuterLevel, _BodyLevel, Context, Environment, [], Context, Hover, Hover).
bind_type_parameters_rigid([type_parameter(Name, Kind, Bound, Span) | Rest], EnvironmentIn, OuterLevel, BodyLevel,
                           ContextIn, EnvironmentOut, SkolemPairs, ContextOut, HoverIn, HoverOut) :-
  ( Kind =:= 0 ->
      convert_bound(Bound, EnvironmentIn, BodyLevel, ContextIn, BoundType, Context1, HoverIn, Hover1),
      fresh_unification_variable(Context1, OuterLevel, Replacement, Context2),
      Replacement = unification_variable(ReplacementId),
      record_variable_bound(Context2, ReplacementId, Name, BoundType, Context3),
      fresh_bound_id(Context3, SkolemId, Context4),
      record_variable_bound(Context4, SkolemId, Name, BoundType, Context5),
      MonoType = skolem(SkolemId, BodyLevel, Name),
      SkolemPairs = [SkolemId - Replacement | RestPairs],
      % The parameter's OWN occurrence (`A` in `<A: Bound>`) gets a hover
      % entry too -- recorded as the bare skolem, so `tt/1`'s existing
      % skolem clause (types.pl/diagnostics.pl) prints the declared name
      % directly during the body; see the module doc above for why a fuller
      % `<Name: Bound>` rendering is reserved for the function's own
      % (generalised) type, not this per-occurrence entry.
      hover_note(Span, type_parameter, MonoType, Hover1, Hover2)
  ; parameter_monotype(Kind, Bound, EnvironmentIn, BodyLevel, ContextIn, MonoType, Context5),
    SkolemPairs = RestPairs,
    Hover2 = HoverIn
  ),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(MonoType, Kind), Environment1),
  bind_type_parameters_rigid(Rest, Environment1, OuterLevel, BodyLevel, Context5, EnvironmentOut, RestPairs, ContextOut, Hover2, HoverOut).

% convert_bound(+Bound, +Environment, +Level, +ContextIn, -BoundType, -ContextOut, +HoverIn, -HoverOut).
%
% `no_bound` stays `no_bound`; a written bound converts to a proper monotype
% at the given level -- unlike `validate_bound/7` (always level 0, used only
% to CHECK a bound is well-formed and then discard it), this is used where
% the bound becomes real, level-sensitive parameter data.  Threading Hover
% here is what lets hovering `Logger` inside `<A: Logger + Named>` show
% `Logger`'s own type (via `convert_proper`'s ordinary node-span recording).
convert_bound(no_bound, _Environment, _Level, Context, no_bound, Context, Hover, Hover).
convert_bound(bound(BoundExpression), Environment, Level, ContextIn, BoundType, ContextOut, HoverIn, HoverOut) :-
  convert_proper(BoundExpression, Environment, [], Level, ContextIn, BoundType, ContextOut, HoverIn, HoverOut).

% A higher-kinded parameter (kind > 0) is always a fresh variable; a proper
% (kind 0) parameter is its converted bound when bounded, else a fresh var.
parameter_monotype(Kind, _Bound, _Environment, Level, ContextIn, MonoType, ContextOut) :-
  Kind > 0, !,
  fresh_unification_variable(ContextIn, Level, MonoType, ContextOut).
parameter_monotype(0, no_bound, _Environment, Level, ContextIn, MonoType, ContextOut) :-
  fresh_unification_variable(ContextIn, Level, MonoType, ContextOut).
parameter_monotype(0, bound(BoundExpression), Environment, Level, ContextIn, MonoType, ContextOut) :-
  convert_proper(BoundExpression, Environment, [], Level, ContextIn, MonoType, ContextOut).

% ---------------------------------------------------------------------------
% Converting surface type expressions to monotypes
% ---------------------------------------------------------------------------

% convert_annotation_type(+TypeExpression, +TypeEnvironment, +Level, +ContextIn, -MonoType, -ContextOut, +HoverIn, -HoverOut).
%
% An annotation must denote a proper type (kind *).
convert_annotation_type(TypeExpression, TypeEnvironment, Level, ContextIn, MonoType, ContextOut, HoverIn, HoverOut) :-
  convert_proper(TypeExpression, TypeEnvironment, [], Level, ContextIn, MonoType, ContextOut, HoverIn, HoverOut).

% Convert a type expression that must be a proper type (kind *), rejecting a
% bare higher-kinded reference used where a value type is expected.
convert_proper(TypeExpression, Environment, Expanding, Level, ContextIn, MonoType, ContextOut, HoverIn, HoverOut) :-
  convert_type(TypeExpression, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut),
  ( Kind =:= 0 ->
      true
  ; throw(analysis_error(higher_kinded_type_not_applied(Kind)))
  ).

convert_proper_each([], _Environment, _Expanding, _Level, Context, [], Context, Hover, Hover).
convert_proper_each([TypeExpression | Rest], Environment, Expanding, Level, ContextIn, [MonoType | MonoTypes], ContextOut, HoverIn, HoverOut) :-
  convert_proper(TypeExpression, Environment, Expanding, Level, ContextIn, MonoType, Context1, HoverIn, Hover1),
  convert_proper_each(Rest, Environment, Expanding, Level, Context1, MonoTypes, ContextOut, Hover1, HoverOut).

% convert_type/10 also yields the type's KIND (its arity: 0 = a proper type,
% k>0 = a constructor awaiting k arguments).
% convert_type(+TypeExpression, +Environment, +Expanding, +Level, +ContextIn, -MonoType, -Kind, -ContextOut, +HoverIn, -HoverOut).
%
% Every clause below records a hover observation at its OWN node's span, using
% the RAW (pre-final-substitution) monotype it just computed -- see
% `hover_note/5`'s doc.  This is what gives every type-expression node in a
% parameter/return/declaration annotation its own hover coverage "for free":
% since every nested type-expression node (a type argument, a record member's
% type, a function type's parameter) is reached by a recursive call back into
% `convert_type`/`convert_proper` regardless of how deeply it is nested inside
% argument lists, sections, or alias expansions, each gets its own entry the
% same way, with no extra bookkeeping at those call sites.
%
% A bare hole `_` is only meaningful as a partial-application argument, where
% `build_reference` consumes it directly; reaching ordinary conversion means it
% was written somewhere it cannot be interpreted.
convert_type(type_hole(_), _Environment, _Expanding, _Level, _ContextIn, _MonoType, _Kind, _ContextOut, Hover, Hover) :- !,
  throw(analysis_error(unexpected_type_hole)).
convert_type(record_type_node(Members, Openness, Span), Environment, Expanding, Level, ContextIn,
             record_type(Fields, Tail), 0, ContextOut, HoverIn, HoverOut) :- !,
  convert_members(Members, 0, Environment, Expanding, Level, ContextIn, Fields, Context1, HoverIn, Hover1),
  tail_for(Openness, Environment, Level, Context1, Tail, ContextOut),
  hover_note(Span, type_record, record_type(Fields, Tail), Hover1, HoverOut).
convert_type(function_type_node(Parameters, Return, Span), Environment, Expanding, Level, ContextIn,
             function_type(ParameterTypes, ReturnType), 0, ContextOut, HoverIn, HoverOut) :- !,
  convert_proper_each(Parameters, Environment, Expanding, Level, ContextIn, ParameterTypes, Context1, HoverIn, Hover1),
  convert_proper(Return, Environment, Expanding, Level, Context1, ReturnType, ContextOut, Hover1, Hover2),
  hover_note(Span, function_type, function_type(ParameterTypes, ReturnType), Hover2, HoverOut).
% A quantified type `<A ..> Body` is a proper (kind-0) POLYTYPE.  Each
% quantifier parameter is bound to a fresh `quantified_variable` so it appears
% bound in the converted body; the result is a `forall_type`.
convert_type(quantified_type_node(Parameters, Body, Span), Environment, Expanding, Level, ContextIn,
             forall_type(BoundIds, BodyType), 0, ContextOut, HoverIn, HoverOut) :- !,
  bind_quantifier_parameters(Parameters, Environment, ContextIn, ScopeEnvironment, BoundIds, Context1, HoverIn, Hover1),
  convert_proper(Body, ScopeEnvironment, Expanding, Level, Context1, BodyType, ContextOut, Hover1, Hover2),
  hover_note(Span, quantified_type, forall_type(BoundIds, BodyType), Hover2, HoverOut).
convert_type(type_name_node(Name, Arguments, Span), Environment, Expanding, Level, ContextIn,
             MonoType, Kind, ContextOut, HoverIn, HoverOut) :-
  ( builtin_type(Name, BaseType) ->
      require_no_arguments(Name, Arguments),
      MonoType = BaseType, Kind = 0, ContextOut = ContextIn, Hover1 = HoverIn
  ; get_assoc(Name, Environment, Entry) ->
      convert_named(Entry, Name, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, Hover1)
  ; get_assoc(constructor_key(Name), Environment, _) ->
      throw(analysis_error(constructor_used_as_type(Name)))
  ; throw(analysis_error(undeclared_type(Name)))
  ),
  hover_note(Span, type_name, MonoType, Hover1, HoverOut).
% An INTERSECTION `B + C (+ ...)` -- always kind 0 (a proper type; an
% intersection is never itself higher-kinded/appliable, unlike a type alias
% whose body might be a section).  Each member is first checked to actually
% BE a module type -- a membership contract -- via `require_module_type_shaped/2`
% below, THEN converted the ordinary way via `convert_proper/6`.  The check
% has to happen on the SURFACE (un-converted) member: once converted, both a
% plain tagged union (e.g. `Optional`) and an opaque module type look
% IDENTICAL as a monotype (`type_constructor(Name, Args)`), so there is no
% way to later tell "this came from `type X = {...}`" apart from "this came
% from `type X = A(..) | B`" by inspecting the MonoType alone -- the
% provenance only exists in the `TypeEnvironment` entry BEFORE conversion,
% which is exactly what `require_module_type_shaped/2` consults.
convert_type(intersection_type_node(Members, Span), Environment, Expanding, Level, ContextIn,
             intersection_type(MonoTypes), 0, ContextOut, HoverIn, HoverOut) :- !,
  convert_intersection_members(Members, Environment, Expanding, Level, ContextIn, MonoTypes, ContextOut, HoverIn, Hover1),
  hover_note(Span, intersection_type, intersection_type(MonoTypes), Hover1, HoverOut).

convert_intersection_members([], _Environment, _Expanding, _Level, Context, [], Context, Hover, Hover).
convert_intersection_members([Member | Rest], Environment, Expanding, Level, ContextIn,
                             [MonoType | MonoTypes], ContextOut, HoverIn, HoverOut) :-
  require_module_type_shaped(Member, Environment),
  convert_proper(Member, Environment, Expanding, Level, ContextIn, MonoType, Context1, HoverIn, Hover1),
  convert_intersection_members(Rest, Environment, Expanding, Level, Context1, MonoTypes, ContextOut, Hover1, HoverOut).

% A member of an intersection must itself be a "membership contract", not an
% arbitrary data type -- `number + string` is meaningless (what value could
% possibly be simultaneously a number AND a string?), so it is rejected here
% rather than producing some nonsensical monotype downstream that would only
% surface as a confusing error much later (or, worse, silently corrupt
% unification -- see the `types.pl` warning about every monotype-shape
% predicate needing an explicit branch).  Two forms qualify:
%   * a literal/anonymous record type expression (`(x: number)`) -- this is
%     ALREADY a structural membership contract on its own, no name needed;
%   * a NAMED reference whose OWN declaration is specifically a
%     `type_module_type_info` (a `type X = {...}` declaration, checked
%     directly against the TypeEnvironment entry, NOT against what it
%     converts to -- see the comment above `convert_type`'s new clause).
% Everything else -- a tagged union, an ordinary alias, an abstract FFI type,
% a bare type parameter, a builtin (`number`/`string`/`boolean`, which are
% never even IN the TypeEnvironment -- see `builtin_type/2` -- so the
% `get_assoc` lookup below simply fails to find them, falling through to the
% same rejection), a function type, or a quantified type -- is rejected by
% the final catch-all clause.
require_module_type_shaped(type_name_node(Name, _Arguments, _), Environment) :- !,
  ( get_assoc(Name, Environment, type_module_type_info(_, _, _)) -> true
  ; throw(analysis_error(not_a_module_type(Name)))
  ).
require_module_type_shaped(record_type_node(_, _, _), _Environment) :- !.
require_module_type_shaped(Member, _Environment) :-
  throw(analysis_error(not_a_module_type_expression(Member))).

% The tail of a record annotation.  A closed record has tail `closed`.  An
% anonymous open record `(.. ..)` gets a fresh row variable.  A captured open
% record `(.. ..R)` reuses the row variable bound to the type parameter `R`,
% so two annotations naming the same `R` share a tail (open-row results).
tail_for(closed, _Environment, _Level, Context, closed, Context).
tail_for(open(anonymous), _Environment, Level, ContextIn, Tail, ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Tail, ContextOut).
tail_for(open(capture(Name)), Environment, _Level, Context, Tail, Context) :-
  ( get_assoc(Name, Environment, type_parameter_binding(Tail, _Kind)) ->
      true
  ; throw(analysis_error(undeclared_row_variable(Name)))
  ).

% A type parameter: bare, it resolves to its monotype with its declared kind;
% applied (`F<A>`), it must be higher-kinded and saturated, yielding a
% `type_application` (kind 0).  A parameter's own arguments are proper types.
convert_named(type_parameter_binding(ParamMono, Arity), Name, Arguments, Environment, Expanding,
              Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut) :-
  length(Arguments, Given),
  ( Given =:= 0 ->
      MonoType = ParamMono, Kind = Arity, ContextOut = ContextIn, HoverOut = HoverIn
  ; Arity =:= 0 ->
      throw(analysis_error(cannot_apply_proper_type(Name)))
  ; Given > Arity ->
      throw(analysis_error(higher_kinded_arity_mismatch(Name, Arity, Given)))
  ; \+ has_hole(Arguments), Given =:= Arity ->
      convert_proper_each(Arguments, Environment, Expanding, Level, ContextIn, ArgumentMonos, ContextOut, HoverIn, HoverOut),
      MonoType = type_application(ParamMono, ArgumentMonos), Kind = 0
  ; % section of a higher-kinded parameter (its positions are all proper)
    zeros(Arity, ParameterKinds),
    build_reference(application(ParamMono), ParameterKinds, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut)
  ).
% A tagged-union type is NOMINAL.
convert_named(type_variant_info(Parameters, _Constructors), Name, Arguments, Environment,
              Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut) :-
  nominal_reference(Name, Parameters, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut).
% An opaque declared type is NOMINAL; a transparent one is a structural alias
% (it must be fully applied -- tier-1 has no higher-kinded aliases).
convert_named(type_declaration_info(opaque, Parameters, _Body), Name, Arguments, Environment,
              Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut) :- !,
  nominal_reference(Name, Parameters, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut).
% A transparent alias expands its body with its parameters bound to the
% leading arguments.  The body may itself be HIGHER-KINDED (a section, e.g.
% `type StringOr = Either<_ string>`): then the alias is higher-kinded too, and
% any SURPLUS arguments are applied to (and beta-reduce) the body.
convert_named(type_declaration_info(transparent, Parameters, Body), Name, Arguments, Environment,
              Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut) :-
  parameter_arity(Parameters, ParameterArity),
  length(Arguments, Given),
  ( Given >= ParameterArity ->
      ( memberchk(Name, Expanding) ->
          throw(analysis_error(cyclic_type_alias(Name)))
      ; true
      ),
      length(ParameterArguments, ParameterArity),
      append(ParameterArguments, ExtraArguments, Arguments),
      parameter_kinds(Parameters, ParameterKinds),
      convert_arguments(ParameterArguments, ParameterKinds, Environment, Expanding, Level, ContextIn, ParameterMonos, Context1, HoverIn, Hover1),
      enforce_bounds(Parameters, ParameterMonos, Environment, Level, Context1, Context2),
      bind_alias_parameters(Parameters, ParameterMonos, Environment, BodyEnvironment),
      convert_type(Body, BodyEnvironment, [Name | Expanding], Level, Context2, BodyMono, BodyKind, Context3, Hover1, Hover2),
      apply_alias_extra(ExtraArguments, BodyMono, BodyKind, Environment, Expanding, Level, Context3, MonoType, Kind, ContextOut, Hover2, HoverOut)
  ; throw(analysis_error(type_constructor_arity_mismatch(Name, ParameterArity, Given)))
  ).

% A module type (module type) is NOMINAL when `opaque` (a module must
% explicitly ascribe to satisfy it, exactly like an opaque alias) or a
% STRUCTURAL row when transparent (the default): expanded to a closed
% `record_type` of its members at the use site, so any value -- a module or an
% ordinary record -- with a compatible shape satisfies it.
convert_named(type_module_type_info(opaque, Parameters, _Members), Name, Arguments, Environment,
              Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut) :- !,
  nominal_reference(Name, Parameters, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut).
convert_named(type_module_type_info(transparent, Parameters, Members), Name, Arguments, Environment,
              Expanding, Level, ContextIn, record_type(Fields, closed), 0, ContextOut, HoverIn, HoverOut) :-
  parameter_arity(Parameters, ParameterArity),
  length(Arguments, Given),
  ( Given =:= ParameterArity ->
      parameter_kinds(Parameters, ParameterKinds),
      convert_arguments(Arguments, ParameterKinds, Environment, Expanding, Level, ContextIn, ArgumentMonos, Context1, HoverIn, Hover1),
      enforce_bounds(Parameters, ArgumentMonos, Environment, Level, Context1, Context2),
      bind_alias_parameters(Parameters, ArgumentMonos, Environment, MemberEnvironment),
      convert_module_type_members(Members, MemberEnvironment, [Name | Expanding], Level, Context2, Fields, ContextOut, Hover1, HoverOut)
  ; throw(analysis_error(type_constructor_arity_mismatch(Name, ParameterArity, Given)))
  ).

% A reference to a NOMINAL type, in one of three forms:
%   * BARE (no arguments): an unapplied `constructor_ref` -- a higher-kinded
%     value of kind = its arity (or the nullary `type_constructor` for arity 0);
%   * SATURATED (all arguments, no holes): a `type_constructor`, kind 0, with
%     each argument kind-checked and any bounds enforced;
%   * a SECTION (holes present, or fewer arguments than the arity): a
%     `type_lambda` awaiting the abstracted positions (see `build_reference`).
nominal_reference(Name, Parameters, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut) :-
  parameter_arity(Parameters, Arity),
  parameter_kinds(Parameters, ParameterKinds),
  length(Arguments, Given),
  ( Given =:= 0 ->
      ( Arity =:= 0 ->
          MonoType = type_constructor(Name, []), Kind = 0
      ; MonoType = constructor_ref(Name), Kind = Arity
      ),
      ContextOut = ContextIn, HoverOut = HoverIn
  ; \+ has_hole(Arguments), Given =:= Arity ->
      convert_arguments(Arguments, ParameterKinds, Environment, Expanding, Level, ContextIn, ArgumentMonos, Context1, HoverIn, Hover1),
      enforce_bounds(Parameters, ArgumentMonos, Environment, Level, Context1, ContextOut),
      MonoType = type_constructor(Name, ArgumentMonos), Kind = 0, HoverOut = Hover1
  ; Given =< Arity ->
      build_reference(nominal(Name), ParameterKinds, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut)
  ; throw(analysis_error(type_constructor_arity_mismatch(Name, Arity, Given)))
  ).

% ---------------------------------------------------------------------------
% Sections (partial type application)
% ---------------------------------------------------------------------------

% Build a SECTION: a `type_lambda` abstracting every hole `_` and every
% missing trailing position of an under-applied reference.  `Builder` says how
% to assemble the saturated body once all positions are filled (`nominal(Name)`
% -> a `type_constructor`; `application(ParamMono)` -> a `type_application`).
% The resulting kind is the number of abstracted positions (its arity).  If
% nothing ends up abstracted, the result is the saturated body at kind 0.
build_reference(Builder, ParameterKinds, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut, HoverIn, HoverOut) :-
  fill_positions(ParameterKinds, Arguments, Environment, Expanding, Level, ContextIn, Slots, AbstractedIds, ContextOut, HoverIn, HoverOut),
  build_head(Builder, Slots, Saturated),
  ( AbstractedIds == [] ->
      MonoType = Saturated, Kind = 0
  ; MonoType = type_lambda(AbstractedIds, Saturated),
    length(AbstractedIds, Kind)
  ).

% Walk the parameter positions, pairing each with the next argument (if any).
% A hole or an exhausted argument list ABSTRACTS the position (binding a fresh
% `quantified_variable`); a present argument is converted and kind-checked.
fill_positions([], _Arguments, _Environment, _Expanding, _Level, Context, [], [], Context, Hover, Hover).
fill_positions([ParameterKind | ParameterKinds], Arguments, Environment, Expanding, Level, ContextIn,
               [Slot | Slots], AbstractedIds, ContextOut, HoverIn, HoverOut) :-
  ( Arguments = [Argument | RestArguments] ->
      true
  ; Argument = type_hole(synthetic), RestArguments = []  % trailing positions abstract
  ),
  ( Argument = type_hole(_) ->
      require_proper_hole_position(ParameterKind),
      fresh_bound_id(ContextIn, Id, Context1),
      Slot = quantified_variable(Id),
      AbstractedIds = [Id | RestAbstractedIds],
      Hover1 = HoverIn
  ; convert_type(Argument, Environment, Expanding, Level, ContextIn, Slot, ActualKind, Context1, HoverIn, Hover1),
    ( ActualKind =:= ParameterKind ->
        true
    ; throw(analysis_error(kind_mismatch(ParameterKind, ActualKind)))
    ),
    ( Slot = forall_type(_, _) ->
        throw(analysis_error(impredicative_type_argument))
    ; true
    ),
    AbstractedIds = RestAbstractedIds
  ),
  fill_positions(ParameterKinds, RestArguments, Environment, Expanding, Level, Context1, Slots, RestAbstractedIds, ContextOut, Hover1, HoverOut).

build_head(nominal(Name), Slots, type_constructor(Name, Slots)).
build_head(application(HeadMono), Slots, type_application(HeadMono, Slots)).

% Tier-1 kinds are arities, so an abstracted position must itself be proper.
require_proper_hole_position(0) :- !.
require_proper_hole_position(_) :-
  throw(analysis_error(higher_kinded_hole_unsupported)).

% Apply a higher-kinded alias body to the alias's SURPLUS arguments.  The body
% must be saturated exactly (tier-1 allows no further re-sectioning here); the
% resulting `type_application` beta-reduces during resolution.
apply_alias_extra([], BodyMono, BodyKind, _Environment, _Expanding, _Level, Context, BodyMono, BodyKind, Context, Hover, Hover).
apply_alias_extra([Argument | Arguments], BodyMono, BodyKind, Environment, Expanding, Level, ContextIn, MonoType, 0, ContextOut, HoverIn, HoverOut) :-
  ExtraArguments = [Argument | Arguments],
  length(ExtraArguments, ExtraCount),
  ( ExtraCount =:= BodyKind ->
      ( has_hole(ExtraArguments) ->
          throw(analysis_error(section_application_hole_unsupported))
      ; true
      ),
      convert_proper_each(ExtraArguments, Environment, Expanding, Level, ContextIn, ExtraMonos, ContextOut, HoverIn, HoverOut),
      MonoType = type_application(BodyMono, ExtraMonos)
  ; throw(analysis_error(higher_kinded_arity_mismatch(alias, BodyKind, ExtraCount)))
  ).

has_hole(Arguments) :-
  memberchk(type_hole(_), Arguments).

zeros(0, []) :- !.
zeros(N, [0 | Rest]) :-
  N > 0,
  N1 is N - 1,
  zeros(N1, Rest).

% Convert each argument, checking its kind against the parameter it fills.
convert_arguments([], [], _Environment, _Expanding, _Level, Context, [], Context, Hover, Hover).
convert_arguments([Argument | Arguments], [ExpectedKind | Kinds], Environment, Expanding, Level,
                  ContextIn, [Mono | Monos], ContextOut, HoverIn, HoverOut) :-
  convert_type(Argument, Environment, Expanding, Level, ContextIn, Mono, ActualKind, Context1, HoverIn, Hover1),
  ( ActualKind =:= ExpectedKind ->
      true
  ; throw(analysis_error(kind_mismatch(ExpectedKind, ActualKind)))
  ),
  % PREDICATIVITY: a type variable stands only for a monotype, so a polytype
  % may not be passed as a type argument (`List<<A>(A): A>` is rejected).
  ( Mono = forall_type(_, _) ->
      throw(analysis_error(impredicative_type_argument))
  ; true
  ),
  convert_arguments(Arguments, Kinds, Environment, Expanding, Level, Context1, Monos, ContextOut, Hover1, HoverOut).

parameter_kinds([], []).
parameter_kinds([type_parameter(_, Kind, _, _) | Rest], [Kind | Kinds]) :-
  parameter_kinds(Rest, Kinds).

parameter_arity(Parameters, Arity) :-
  length(Parameters, Arity).

% Bounds (only on proper-kind parameters) are proper types.
%
% A bound is a SATISFACTION constraint, not an equality constraint: the
% argument must merely be AT LEAST as capable as the bound, so `subsume/5`
% (not `unify/4`) is the right check -- the same "actual is at least as
% polymorphic/capable as expected" primitive used for Rank-N generics and for
% module-ascription conformance.  This is a deliberate upgrade from this
% predicate's old behaviour (it used to call `unify/4`, requiring the
% argument to be EXACTLY the bound, which would have made a multi-bound
% `<A: B + C>` nearly useless -- it would force the caller to pass literally
% an `intersection_type([B, C])`, rather than accepting any type that merely
% has both B's and C's capabilities).  `subsume`'s own dispatch already knows
% how to check "Argument satisfies an intersection bound" via its
% EXPECTED-is-intersection rule in types.pl (require every member
% satisfied), so `<A: B + C>` needs no special handling AT ALL here --
% `BoundType` converts to `intersection_type([...])` like any other type
% expression (see `type_environment.pl`'s `convert_type` clause for
% `intersection_type_node`), and this predicate calls `subsume` on it exactly
% the same as a single, ordinary bound.
enforce_bounds([], [], _Environment, _Level, Context, Context).
enforce_bounds([type_parameter(_, _Kind, no_bound, _) | Parameters], [_Argument | Arguments], Environment,
               Level, ContextIn, ContextOut) :-
  enforce_bounds(Parameters, Arguments, Environment, Level, ContextIn, ContextOut).
enforce_bounds([type_parameter(_, _Kind, bound(BoundExpression), _) | Parameters], [Argument | Arguments],
               Environment, Level, ContextIn, ContextOut) :-
  % A THROWAWAY scratch hover pair: this bound expression is the SAME source
  % node already recorded (with real hover) wherever this parameter's own
  % `<T: Bound>` was bound (`bind_quantifier_parameters`/`convert_bound`) --
  % re-converting it here is purely a SATISFACTION check, not a fresh
  % occurrence worth a second, redundant entry.
  convert_proper(BoundExpression, Environment, [], Level, ContextIn, BoundType, Context1, [], _),
  subsume(Argument, BoundType, Level, Context1, Context2),
  enforce_bounds(Parameters, Arguments, Environment, Level, Context2, ContextOut).

bind_alias_parameters([], [], Environment, Environment).
bind_alias_parameters([type_parameter(Name, Kind, _Bound, _) | Parameters], [Argument | Arguments],
                      EnvironmentIn, EnvironmentOut) :-
  put_assoc(Name, EnvironmentIn, type_parameter_binding(Argument, Kind), Environment1),
  bind_alias_parameters(Parameters, Arguments, Environment1, EnvironmentOut).

% A record type's members become keyed fields: positional members get
% sequential `index` keys, labeled members get `label` keys.
convert_members([], _Index, _Environment, _Expanding, _Level, Context, [], Context, Hover, Hover).
convert_members([record_type_member(Mutability, Label, TypeExpression, _) | Members], Index,
                Environment, Expanding, Level, ContextIn,
                [record_field(Mutability, Key, Type) | Fields], ContextOut, HoverIn, HoverOut) :-
  type_member_key(Label, Index, Key, NextIndex),
  convert_proper(TypeExpression, Environment, Expanding, Level, ContextIn, Type, Context1, HoverIn, Hover1),
  convert_members(Members, NextIndex, Environment, Expanding, Level, Context1, Fields, ContextOut, Hover1, HoverOut).

type_member_key(positional, Index, index(Index), NextIndex) :-
  NextIndex is Index + 1.
type_member_key(labeled(Name), Index, label(Name), Index).

% A module type's members become a closed row of readonly, labeled fields --
% every member is named, so there is no positional form to key by index.
convert_module_type_members([], _Environment, _Expanding, _Level, Context, [], Context, Hover, Hover).
convert_module_type_members([module_type_member(Name, TypeExpression, _) | Members], Environment, Expanding, Level,
                          ContextIn, [record_field(readonly, label(Name), Type) | Fields], ContextOut, HoverIn, HoverOut) :-
  convert_proper(TypeExpression, Environment, Expanding, Level, ContextIn, Type, Context1, HoverIn, Hover1),
  convert_module_type_members(Members, Environment, Expanding, Level, Context1, Fields, ContextOut, Hover1, HoverOut).

% module_type_row_for(+Name, +Arguments, +Environment, +Level, +ContextIn, -Fields, -ContextOut).
%
% Resolve a KNOWN module type name to its member row given ALREADY-CONVERTED
% monotype arguments (e.g. from a resolved `type_constructor(Name, Arguments)`).
% Used for nominal field access and module-ascription conformance checking,
% both of which must see a module type's actual shape regardless of its own
% opacity (opacity governs whether OTHER differently-named values may
% substitute for it, not whether its own values support member access).  Not
% itself reached from any surface annotation span (its callers are member
% ACCESS and bound resolution, not annotation conversion), so it threads a
% throwaway scratch hover pair through `convert_module_type_members`
% internally rather than exposing Hover in its own (external) contract.
module_type_row_for(Name, Arguments, Environment, Level, ContextIn, Fields, ContextOut) :-
  ( get_assoc(Name, Environment, type_module_type_info(_Opacity, Parameters, Members)) ->
      bind_alias_parameters(Parameters, Arguments, Environment, MemberEnvironment),
      convert_module_type_members(Members, MemberEnvironment, [Name], Level, ContextIn, Fields, ContextOut, [], _)
  ; throw(analysis_error(unknown_member_target(Name)))
  ).

% bound_row_fields(+Bound, +Environment, +Level, +ContextIn, -Fields, -ContextOut).
%
% Resolve a bounded generic parameter's already-CONVERTED bound to the field
% row its capabilities expose, for member access on a rigid skolem (see
% infer.pl's `access_node` clause).  `require_module_type_shaped/2` already
% guarantees, at the point a bound is first converted (see
% `convert_intersection_members`/`convert_type`'s `intersection_type_node`
% clause), that every member is either a literal anonymous record type or a
% reference to a `type X = { .. }` declaration -- so a bound's converted form
% is always one of exactly these three shapes: a bare `record_type` (a
% TRANSPARENT module type, or a literal record annotation, converts directly
% to one), a `type_constructor` (an OPAQUE module type stays nominal, so its
% row must be looked up by name), or an `intersection_type` of several such
% members (`A: B + C`).
%
% An intersection's fields are a WIDTH UNION: possessing every member's
% capabilities means every member's fields are available, exactly mirroring
% `subsume_resolved`'s ACTUAL-is-intersection rule in types.pl (a value
% satisfying `B + C` may be used wherever a plain `B`, or a plain `C`, is
% independently expected -- so, symmetrically, its accessible fields are the
% union of both).
bound_row_fields(record_type(Fields, _Tail), _Environment, _Level, Context, Fields, Context) :- !.
bound_row_fields(type_constructor(Name, Arguments), Environment, Level, ContextIn, Fields, ContextOut) :- !,
  module_type_row_for(Name, Arguments, Environment, Level, ContextIn, Fields, ContextOut).
bound_row_fields(intersection_type(Members), Environment, Level, ContextIn, Fields, ContextOut) :- !,
  bound_row_fields_each(Members, Environment, Level, ContextIn, FieldLists, ContextOut),
  append(FieldLists, Fields).

bound_row_fields_each([], _Environment, _Level, Context, [], Context).
bound_row_fields_each([Member | Members], Environment, Level, ContextIn, [Fields | Rest], ContextOut) :-
  bound_row_fields(Member, Environment, Level, ContextIn, Fields, Context1),
  bound_row_fields_each(Members, Environment, Level, Context1, Rest, ContextOut).

% ---------------------------------------------------------------------------
% Seeding `external` declarations (shared by the top-level pipeline and a
% nested module body's own inner scope -- see infer.pl's module_node case).
% ---------------------------------------------------------------------------

% seed_externals(+Items, +TypeEnvironment, +Level, +EnvironmentIn, +ContextIn, -EnvironmentOut, -ContextOut).
%
% Bind every `external Name: Type = ...` (foreign JS import) among `Items`
% into the environment.  The ascribed `Type` is converted to a monotype and
% generalised into a scheme exactly as a top-level annotation would be --
% there is no value to check it against, so the type is simply trusted (this
% is the one unsafe point of the JS boundary).  Binding them up front (before
% inference walks the items) makes every external visible throughout its
% scope, like a constant.  Non-`external` items are left for the inference
% walk.
seed_externals([], _TypeEnvironment, _Level, Environment, Context, Environment, Context, Hover, Hover).
seed_externals([external_node(Name, TypeExpression, Source, _, _) | Rest], TypeEnvironment, Level,
               EnvironmentIn, ContextIn, EnvironmentOut, ContextOut, HoverIn, HoverOut) :- !,
  validate_external_source(Source),
  Level1 is Level + 1,
  convert_annotation_type(TypeExpression, TypeEnvironment, Level1, ContextIn, MonoType, Context1, HoverIn, Hover1),
  generalize(MonoType, Level, Context1, Scheme, Context2),
  put_assoc(Name, EnvironmentIn, defined(Scheme), Environment1),
  seed_externals(Rest, TypeEnvironment, Level, Environment1, Context2, EnvironmentOut, ContextOut, Hover1, HoverOut).
seed_externals([_Other | Rest], TypeEnvironment, Level, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut, HoverIn, HoverOut) :-
  seed_externals(Rest, TypeEnvironment, Level, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut, HoverIn, HoverOut).

% A renamed module import (`= 'foreign' from 'module'`) names a JS export that
% codegen splices, unescaped, into `import { Foreign } from ...` -- so it must
% be a valid JS identifier or it would break (or inject into) the emitted
% import.  The other source forms put no name in identifier position: a
% `js_global` / same-name `default` import reuses the (already-valid) declared
% name, and a `js_expression` is trusted verbatim.
validate_external_source(js_module(_Module, named(Foreign))) :- !,
  ( js_identifier(Foreign) -> true
  ; throw(analysis_error(invalid_external_name(Foreign)))
  ).
validate_external_source(_Source).

% A JS IdentifierName, on the language's own Unicode identifier basis (UAX #31
% XID_Start / XID_Continue, via `unicode`) plus the two characters JS allows
% that XID does not: `$` (in neither set) and a leading `_` (XID_Continue but
% not XID_Start).  So foreign names are exactly as permissive as the language's
% own identifiers.
js_identifier([First | Rest]) :-
  js_identifier_start(First),
  maplist(js_identifier_continue, Rest).

js_identifier_start(Char) :-
  char_code(Char, Code),
  ( Code =:= 0'_ ; Code =:= 0'$ ; xid_start(Code) ).

js_identifier_continue(Char) :-
  char_code(Char, Code),
  ( Code =:= 0'$ ; xid_continue(Code) ).   % `_` is already in XID_Continue

require_no_arguments(_, []) :- !.
require_no_arguments(Name, _) :-
  throw(analysis_error(type_not_parameterized(Name))).

builtin_type("number", number).
builtin_type("boolean", boolean).
builtin_type("string", string).

parameter_names([], []).
parameter_names([type_parameter(Name, _Kind, _Bound, _) | Parameters], [Name | Names]) :-
  parameter_names(Parameters, Names).

has_duplicate([Element | Rest]) :-
  ( memberchk(Element, Rest) -> true ; has_duplicate(Rest) ).
