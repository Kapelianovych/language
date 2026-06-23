:- module(type_environment, [
  build_type_environment/3,
  convert_annotation_type/6,
  bind_type_parameters/6,
  instantiate_constructor/7,
  union_constructor_names/3
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
  unify/4
]).

% ---------------------------------------------------------------------------
% Building the environment
% ---------------------------------------------------------------------------

%% build_type_environment(+ProgramNode, -TypeEnvironment, -ConstructorBindings).
%
% `TypeEnvironment` maps type names to their info and variant constructor
% names to `variant_constructor(...)`.  `ConstructorBindings` is a list of
% `CtorName - Scheme` term bindings (each constructor as a function/value),
% to seed the term environment so constructors can be used in expressions.
build_type_environment(program_node(Expressions), TypeEnvironment, ConstructorBindings) :-
  collect_declarations(Expressions, Declarations),
  empty_assoc(Empty),
  register_declarations(Declarations, Empty, TypeEnvironment),
  validate_declarations(Declarations, TypeEnvironment),
  build_constructor_bindings(Declarations, TypeEnvironment, ConstructorBindings).

collect_declarations([], []).
collect_declarations([type_declaration_node(Name, Parameters, Opacity, Body) | Rest],
                     [type_declaration_node(Name, Parameters, Opacity, Body) | Declarations]) :- !,
  collect_declarations(Rest, Declarations).
collect_declarations([_ | Rest], Declarations) :-
  collect_declarations(Rest, Declarations).

register_declarations([], Environment, Environment).
% A tagged-union declaration: register the (nominal) type AND each of its
% constructors (so they can be looked up for construction and matching).
register_declarations([type_declaration_node(Name, Parameters, _Opacity, variant_body(Constructors)) | Rest],
                      EnvironmentIn, EnvironmentOut) :- !,
  register_type_name(Name, Parameters, EnvironmentIn),
  put_assoc(Name, EnvironmentIn, type_variant_info(Parameters, Constructors), Environment1),
  register_constructors(Constructors, Name, Parameters, Environment1, Environment2),
  register_declarations(Rest, Environment2, EnvironmentOut).
register_declarations([type_declaration_node(Name, Parameters, Opacity, Body) | Rest],
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
register_constructors([constructor(CtorName, FieldTypes) | Rest], Union, Parameters,
                      EnvironmentIn, EnvironmentOut) :-
  ( get_assoc(constructor_key(CtorName), EnvironmentIn, _) ->
      throw(analysis_error(duplicate_constructor(CtorName)))
  ; true
  ),
  put_assoc(constructor_key(CtorName), EnvironmentIn, variant_constructor(Union, Parameters, FieldTypes), Environment1),
  register_constructors(Rest, Union, Parameters, Environment1, EnvironmentOut).

% Validate each declaration's bounds and body in a throwaway context (the
% fresh variables it mints are discarded).  Marking the declaration's own
% name as being expanded catches structural self-cycles.
validate_declarations([], _).
validate_declarations([type_declaration_node(_Name, Parameters, _Opacity, variant_body(Constructors)) | Rest], TypeEnvironment) :- !,
  empty_context(Context0),
  bind_validation_parameters(Parameters, TypeEnvironment, Context0, ValidationEnvironment, Context1),
  validate_constructor_fields(Constructors, ValidationEnvironment, Context1),
  validate_declarations(Rest, TypeEnvironment).
validate_declarations([type_declaration_node(Name, Parameters, _Opacity, Body) | Rest], TypeEnvironment) :-
  empty_context(Context0),
  bind_validation_parameters(Parameters, TypeEnvironment, Context0, ValidationEnvironment, Context1),
  % The body may be higher-kinded (an alias bound to a SECTION), so do not
  % force kind 0 here; a higher-kinded alias used in a proper position is
  % rejected at the USE site by `convert_proper`.
  convert_type(Body, ValidationEnvironment, [Name], 0, Context1, _Validated, _Kind, _Context2),
  validate_declarations(Rest, TypeEnvironment).

validate_constructor_fields([], _Environment, _Context).
validate_constructor_fields([constructor(_Name, FieldTypes) | Rest], Environment, ContextIn) :-
  convert_field_types(FieldTypes, Environment, 0, ContextIn, _ConvertedFields, Context1),
  validate_constructor_fields(Rest, Environment, Context1).

% Convert a constructor's positional field type expressions (each proper).
convert_field_types([], _Environment, _Level, Context, [], Context).
convert_field_types([FieldExpression | Rest], Environment, Level, ContextIn, [FieldType | FieldTypes], ContextOut) :-
  convert_proper(FieldExpression, Environment, [], Level, ContextIn, FieldType, Context1),
  convert_field_types(Rest, Environment, Level, Context1, FieldTypes, ContextOut).

% ---------------------------------------------------------------------------
% Constructors as values, and constructor instantiation for patterns
% ---------------------------------------------------------------------------

% Build a term binding (a type scheme) for every variant constructor.  A
% constructor `C(t1 .. tn)` of `type U<p1 .. pk> = ...` gets the scheme
% forall p1..pk. (t1 .. tn) -> U<p1 .. pk>; a nullary constructor is just a
% value of type U<p1 .. pk>.
build_constructor_bindings([], _TypeEnvironment, []).
build_constructor_bindings([type_declaration_node(Name, Parameters, _Opacity, variant_body(Constructors)) | Rest],
                           TypeEnvironment, Bindings) :- !,
  constructor_schemes(Constructors, Name, Parameters, TypeEnvironment, ThisBindings),
  build_constructor_bindings(Rest, TypeEnvironment, RestBindings),
  append(ThisBindings, RestBindings, Bindings).
build_constructor_bindings([_ | Rest], TypeEnvironment, Bindings) :-
  build_constructor_bindings(Rest, TypeEnvironment, Bindings).

constructor_schemes([], _Union, _Parameters, _TypeEnvironment, []).
constructor_schemes([constructor(CtorName, FieldExpressions) | Rest], Union, Parameters, TypeEnvironment,
                    [CtorName - Scheme | Schemes]) :-
  constructor_scheme(Union, Parameters, FieldExpressions, TypeEnvironment, Scheme),
  constructor_schemes(Rest, Union, Parameters, TypeEnvironment, Schemes).

constructor_scheme(Union, Parameters, FieldExpressions, TypeEnvironment, type_scheme(QuantifiedIds, Body)) :-
  quantified_parameter_scope(Parameters, 0, TypeEnvironment, ScopeEnvironment, QuantifiedVariables, QuantifiedIds),
  empty_context(Context0),
  convert_field_types(FieldExpressions, ScopeEnvironment, 0, Context0, FieldTypes, _Context1),
  Result = type_constructor(Union, QuantifiedVariables),
  ( FieldTypes == [] ->
      Body = Result
  ; Body = function_type(FieldTypes, Result)
  ).

% Bind each parameter to `quantified_variable(Index)` (the scheme's bound
% variables) and collect those variables and their ids.
quantified_parameter_scope([], _Index, Environment, Environment, [], []).
quantified_parameter_scope([type_parameter(Name, Kind, _Bound) | Rest], Index, EnvironmentIn, EnvironmentOut,
                           [quantified_variable(Index) | Variables], [Index | Ids]) :-
  put_assoc(Name, EnvironmentIn, type_parameter_binding(quantified_variable(Index), Kind), Environment1),
  Index1 is Index + 1,
  quantified_parameter_scope(Rest, Index1, Environment1, EnvironmentOut, Variables, Ids).

%% instantiate_constructor(+CtorName, +TypeEnvironment, +Level, +ContextIn, -UnionType, -FieldTypes, -ContextOut).
%
% For pattern matching: produce the constructor's union type and field types
% with the union's parameters freshly instantiated at `Level`.
instantiate_constructor(CtorName, TypeEnvironment, Level, ContextIn, UnionType, FieldTypes, ContextOut) :-
  ( get_assoc(constructor_key(CtorName), TypeEnvironment, variant_constructor(Union, Parameters, FieldExpressions)) ->
      fresh_parameter_scope(Parameters, TypeEnvironment, Level, ContextIn, ScopeEnvironment, FreshVariables, Context1),
      UnionType = type_constructor(Union, FreshVariables),
      convert_field_types(FieldExpressions, ScopeEnvironment, Level, Context1, FieldTypes, ContextOut)
  ; throw(analysis_error(unknown_constructor(CtorName)))
  ).

fresh_parameter_scope([], Environment, _Level, Context, Environment, [], Context).
fresh_parameter_scope([type_parameter(Name, Kind, _Bound) | Rest], EnvironmentIn, Level, ContextIn,
                      EnvironmentOut, [Fresh | Variables], ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Fresh, Context1),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(Fresh, Kind), Environment1),
  fresh_parameter_scope(Rest, Environment1, Level, Context1, EnvironmentOut, Variables, ContextOut).

%% union_constructor_names(+UnionName, +TypeEnvironment, -Names).
union_constructor_names(UnionName, TypeEnvironment, Names) :-
  get_assoc(UnionName, TypeEnvironment, type_variant_info(_Parameters, Constructors)),
  findall(Name, member(constructor(Name, _Fields), Constructors), Names).

% Bind each parameter to a fresh placeholder for validation, after checking
% its bound is itself well-formed.
bind_validation_parameters([], Environment, Context, Environment, Context).
bind_validation_parameters([type_parameter(Name, Kind, Bound) | Rest], EnvironmentIn, ContextIn,
                           EnvironmentOut, ContextOut) :-
  validate_bound(Bound, EnvironmentIn, ContextIn, Context1),
  fresh_unification_variable(Context1, 0, Placeholder, Context2),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(Placeholder, Kind), Environment1),
  bind_validation_parameters(Rest, Environment1, Context2, EnvironmentOut, ContextOut).

validate_bound(no_bound, _Environment, Context, Context).
validate_bound(bound(BoundExpression), Environment, ContextIn, ContextOut) :-
  convert_proper(BoundExpression, Environment, [], 0, ContextIn, _BoundType, ContextOut).

% Bind a quantified type's parameters: each becomes a fresh, globally-unique
% `quantified_variable` (so it is BOUND in the resulting `forall_type` body),
% carrying its declared kind.  A bound, if written, is checked well-formed (a
% later parameter's bound may mention an earlier one), as in declarations.
bind_quantifier_parameters([], Environment, Context, Environment, [], Context).
bind_quantifier_parameters([type_parameter(Name, Kind, Bound) | Rest], EnvironmentIn, ContextIn,
                           EnvironmentOut, [Id | Ids], ContextOut) :-
  validate_bound(Bound, EnvironmentIn, ContextIn, Context1),
  fresh_bound_id(Context1, Id, Context2),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(quantified_variable(Id), Kind), Environment1),
  bind_quantifier_parameters(Rest, Environment1, Context2, EnvironmentOut, Ids, ContextOut).

% ---------------------------------------------------------------------------
% Binding function/anonymous type parameters into an environment
% ---------------------------------------------------------------------------

%% bind_type_parameters(+TypeParameters, +EnvironmentIn, +Level, +ContextIn, -EnvironmentOut, -ContextOut).
%
% Extend an environment with a function's generics.  An unbounded parameter
% becomes a fresh type variable; a bounded one becomes its converted bound
% (e.g. an open record), so references to the parameter carry the bound.
% A later parameter's bound may mention an earlier one.
bind_type_parameters([], Environment, _Level, Context, Environment, Context).
bind_type_parameters([type_parameter(Name, Kind, Bound) | Rest], EnvironmentIn, Level, ContextIn,
                     EnvironmentOut, ContextOut) :-
  parameter_monotype(Kind, Bound, EnvironmentIn, Level, ContextIn, MonoType, Context1),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(MonoType, Kind), Environment1),
  bind_type_parameters(Rest, Environment1, Level, Context1, EnvironmentOut, ContextOut).

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

%% convert_annotation_type(+TypeExpression, +TypeEnvironment, +Level, +ContextIn, -MonoType, -ContextOut).
%
% An annotation must denote a proper type (kind *).
convert_annotation_type(TypeExpression, TypeEnvironment, Level, ContextIn, MonoType, ContextOut) :-
  convert_proper(TypeExpression, TypeEnvironment, [], Level, ContextIn, MonoType, ContextOut).

% Convert a type expression that must be a proper type (kind *), rejecting a
% bare higher-kinded reference used where a value type is expected.
convert_proper(TypeExpression, Environment, Expanding, Level, ContextIn, MonoType, ContextOut) :-
  convert_type(TypeExpression, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut),
  ( Kind =:= 0 ->
      true
  ; throw(analysis_error(higher_kinded_type_not_applied(Kind)))
  ).

convert_proper_each([], _Environment, _Expanding, _Level, Context, [], Context).
convert_proper_each([TypeExpression | Rest], Environment, Expanding, Level, ContextIn, [MonoType | MonoTypes], ContextOut) :-
  convert_proper(TypeExpression, Environment, Expanding, Level, ContextIn, MonoType, Context1),
  convert_proper_each(Rest, Environment, Expanding, Level, Context1, MonoTypes, ContextOut).

% convert_type/8 also yields the type's KIND (its arity: 0 = a proper type,
% k>0 = a constructor awaiting k arguments).
% convert_type(+TypeExpression, +Environment, +Expanding, +Level, +ContextIn, -MonoType, -Kind, -ContextOut).
% A bare hole `_` is only meaningful as a partial-application argument, where
% `build_reference` consumes it directly; reaching ordinary conversion means it
% was written somewhere it cannot be interpreted.
convert_type(type_hole, _Environment, _Expanding, _Level, _ContextIn, _MonoType, _Kind, _ContextOut) :- !,
  throw(analysis_error(unexpected_type_hole)).
convert_type(tuple_type_node(Members, Openness), Environment, Expanding, Level, ContextIn,
             tuple_type(Fields, Tail), 0, ContextOut) :- !,
  convert_members(Members, 0, Environment, Expanding, Level, ContextIn, Fields, Context1),
  tail_for(Openness, Environment, Level, Context1, Tail, ContextOut).
convert_type(function_type_node(Parameters, Return), Environment, Expanding, Level, ContextIn,
             function_type(ParameterTypes, ReturnType), 0, ContextOut) :- !,
  convert_proper_each(Parameters, Environment, Expanding, Level, ContextIn, ParameterTypes, Context1),
  convert_proper(Return, Environment, Expanding, Level, Context1, ReturnType, ContextOut).
% A quantified type `<A ..> Body` is a proper (kind-0) POLYTYPE.  Each
% quantifier parameter is bound to a fresh `quantified_variable` so it appears
% bound in the converted body; the result is a `forall_type`.
convert_type(quantified_type_node(Parameters, Body), Environment, Expanding, Level, ContextIn,
             forall_type(BoundIds, BodyType), 0, ContextOut) :- !,
  bind_quantifier_parameters(Parameters, Environment, ContextIn, ScopeEnvironment, BoundIds, Context1),
  convert_proper(Body, ScopeEnvironment, Expanding, Level, Context1, BodyType, ContextOut).
convert_type(type_name_node(Name, Arguments), Environment, Expanding, Level, ContextIn,
             MonoType, Kind, ContextOut) :-
  ( builtin_type(Name, BaseType) ->
      require_no_arguments(Name, Arguments),
      MonoType = BaseType, Kind = 0, ContextOut = ContextIn
  ; get_assoc(Name, Environment, Entry) ->
      convert_named(Entry, Name, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut)
  ; get_assoc(constructor_key(Name), Environment, _) ->
      throw(analysis_error(constructor_used_as_type(Name)))
  ; throw(analysis_error(undeclared_type(Name)))
  ).

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
              Level, ContextIn, MonoType, Kind, ContextOut) :-
  length(Arguments, Given),
  ( Given =:= 0 ->
      MonoType = ParamMono, Kind = Arity, ContextOut = ContextIn
  ; Arity =:= 0 ->
      throw(analysis_error(cannot_apply_proper_type(Name)))
  ; Given > Arity ->
      throw(analysis_error(higher_kinded_arity_mismatch(Name, Arity, Given)))
  ; \+ has_hole(Arguments), Given =:= Arity ->
      convert_proper_each(Arguments, Environment, Expanding, Level, ContextIn, ArgumentMonos, ContextOut),
      MonoType = type_application(ParamMono, ArgumentMonos), Kind = 0
  ; % section of a higher-kinded parameter (its positions are all proper)
    zeros(Arity, ParameterKinds),
    build_reference(application(ParamMono), ParameterKinds, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut)
  ).
% A tagged-union type is NOMINAL.
convert_named(type_variant_info(Parameters, _Constructors), Name, Arguments, Environment,
              Expanding, Level, ContextIn, MonoType, Kind, ContextOut) :-
  nominal_reference(Name, Parameters, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut).
% An opaque declared type is NOMINAL; a transparent one is a structural alias
% (it must be fully applied -- tier-1 has no higher-kinded aliases).
convert_named(type_declaration_info(opaque, Parameters, _Body), Name, Arguments, Environment,
              Expanding, Level, ContextIn, MonoType, Kind, ContextOut) :- !,
  nominal_reference(Name, Parameters, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut).
% A transparent alias expands its body with its parameters bound to the
% leading arguments.  The body may itself be HIGHER-KINDED (a section, e.g.
% `type StringOr = Either<_ string>`): then the alias is higher-kinded too, and
% any SURPLUS arguments are applied to (and beta-reduce) the body.
convert_named(type_declaration_info(transparent, Parameters, Body), Name, Arguments, Environment,
              Expanding, Level, ContextIn, MonoType, Kind, ContextOut) :-
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
      convert_arguments(ParameterArguments, ParameterKinds, Environment, Expanding, Level, ContextIn, ParameterMonos, Context1),
      enforce_bounds(Parameters, ParameterMonos, Environment, Level, Context1, Context2),
      bind_alias_parameters(Parameters, ParameterMonos, Environment, BodyEnvironment),
      convert_type(Body, BodyEnvironment, [Name | Expanding], Level, Context2, BodyMono, BodyKind, Context3),
      apply_alias_extra(ExtraArguments, BodyMono, BodyKind, Environment, Expanding, Level, Context3, MonoType, Kind, ContextOut)
  ; throw(analysis_error(type_constructor_arity_mismatch(Name, ParameterArity, Given)))
  ).

% A reference to a NOMINAL type, in one of three forms:
%   * BARE (no arguments): an unapplied `constructor_ref` -- a higher-kinded
%     value of kind = its arity (or the nullary `type_constructor` for arity 0);
%   * SATURATED (all arguments, no holes): a `type_constructor`, kind 0, with
%     each argument kind-checked and any bounds enforced;
%   * a SECTION (holes present, or fewer arguments than the arity): a
%     `type_lambda` awaiting the abstracted positions (see `build_reference`).
nominal_reference(Name, Parameters, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut) :-
  parameter_arity(Parameters, Arity),
  parameter_kinds(Parameters, ParameterKinds),
  length(Arguments, Given),
  ( Given =:= 0 ->
      ( Arity =:= 0 ->
          MonoType = type_constructor(Name, []), Kind = 0
      ; MonoType = constructor_ref(Name), Kind = Arity
      ),
      ContextOut = ContextIn
  ; \+ has_hole(Arguments), Given =:= Arity ->
      convert_arguments(Arguments, ParameterKinds, Environment, Expanding, Level, ContextIn, ArgumentMonos, Context1),
      enforce_bounds(Parameters, ArgumentMonos, Environment, Level, Context1, ContextOut),
      MonoType = type_constructor(Name, ArgumentMonos), Kind = 0
  ; Given =< Arity ->
      build_reference(nominal(Name), ParameterKinds, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut)
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
build_reference(Builder, ParameterKinds, Arguments, Environment, Expanding, Level, ContextIn, MonoType, Kind, ContextOut) :-
  fill_positions(ParameterKinds, Arguments, Environment, Expanding, Level, ContextIn, Slots, AbstractedIds, ContextOut),
  build_head(Builder, Slots, Saturated),
  ( AbstractedIds == [] ->
      MonoType = Saturated, Kind = 0
  ; MonoType = type_lambda(AbstractedIds, Saturated),
    length(AbstractedIds, Kind)
  ).

% Walk the parameter positions, pairing each with the next argument (if any).
% A hole or an exhausted argument list ABSTRACTS the position (binding a fresh
% `quantified_variable`); a present argument is converted and kind-checked.
fill_positions([], _Arguments, _Environment, _Expanding, _Level, Context, [], [], Context).
fill_positions([ParameterKind | ParameterKinds], Arguments, Environment, Expanding, Level, ContextIn,
               [Slot | Slots], AbstractedIds, ContextOut) :-
  ( Arguments = [Argument | RestArguments] ->
      true
  ; Argument = type_hole, RestArguments = []        % trailing positions abstract
  ),
  ( Argument == type_hole ->
      require_proper_hole_position(ParameterKind),
      fresh_bound_id(ContextIn, Id, Context1),
      Slot = quantified_variable(Id),
      AbstractedIds = [Id | RestAbstractedIds]
  ; convert_type(Argument, Environment, Expanding, Level, ContextIn, Slot, ActualKind, Context1),
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
  fill_positions(ParameterKinds, RestArguments, Environment, Expanding, Level, Context1, Slots, RestAbstractedIds, ContextOut).

build_head(nominal(Name), Slots, type_constructor(Name, Slots)).
build_head(application(HeadMono), Slots, type_application(HeadMono, Slots)).

% Tier-1 kinds are arities, so an abstracted position must itself be proper.
require_proper_hole_position(0) :- !.
require_proper_hole_position(_) :-
  throw(analysis_error(higher_kinded_hole_unsupported)).

% Apply a higher-kinded alias body to the alias's SURPLUS arguments.  The body
% must be saturated exactly (tier-1 allows no further re-sectioning here); the
% resulting `type_application` beta-reduces during resolution.
apply_alias_extra([], BodyMono, BodyKind, _Environment, _Expanding, _Level, Context, BodyMono, BodyKind, Context).
apply_alias_extra([Argument | Arguments], BodyMono, BodyKind, Environment, Expanding, Level, ContextIn, MonoType, 0, ContextOut) :-
  ExtraArguments = [Argument | Arguments],
  length(ExtraArguments, ExtraCount),
  ( ExtraCount =:= BodyKind ->
      ( has_hole(ExtraArguments) ->
          throw(analysis_error(section_application_hole_unsupported))
      ; true
      ),
      convert_proper_each(ExtraArguments, Environment, Expanding, Level, ContextIn, ExtraMonos, ContextOut),
      MonoType = type_application(BodyMono, ExtraMonos)
  ; throw(analysis_error(higher_kinded_arity_mismatch(alias, BodyKind, ExtraCount)))
  ).

has_hole(Arguments) :-
  memberchk(type_hole, Arguments).

zeros(0, []) :- !.
zeros(N, [0 | Rest]) :-
  N > 0,
  N1 is N - 1,
  zeros(N1, Rest).

% Convert each argument, checking its kind against the parameter it fills.
convert_arguments([], [], _Environment, _Expanding, _Level, Context, [], Context).
convert_arguments([Argument | Arguments], [ExpectedKind | Kinds], Environment, Expanding, Level,
                  ContextIn, [Mono | Monos], ContextOut) :-
  convert_type(Argument, Environment, Expanding, Level, ContextIn, Mono, ActualKind, Context1),
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
  convert_arguments(Arguments, Kinds, Environment, Expanding, Level, Context1, Monos, ContextOut).

parameter_kinds([], []).
parameter_kinds([type_parameter(_, Kind, _) | Rest], [Kind | Kinds]) :-
  parameter_kinds(Rest, Kinds).

parameter_arity(Parameters, Arity) :-
  length(Parameters, Arity).

% Bounds (only on proper-kind parameters) are proper types.
enforce_bounds([], [], _Environment, _Level, Context, Context).
enforce_bounds([type_parameter(_, _Kind, no_bound) | Parameters], [_Argument | Arguments], Environment,
               Level, ContextIn, ContextOut) :-
  enforce_bounds(Parameters, Arguments, Environment, Level, ContextIn, ContextOut).
enforce_bounds([type_parameter(_, _Kind, bound(BoundExpression)) | Parameters], [Argument | Arguments],
               Environment, Level, ContextIn, ContextOut) :-
  convert_proper(BoundExpression, Environment, [], Level, ContextIn, BoundType, Context1),
  unify(Argument, BoundType, Context1, Context2),
  enforce_bounds(Parameters, Arguments, Environment, Level, Context2, ContextOut).

bind_alias_parameters([], [], Environment, Environment).
bind_alias_parameters([type_parameter(Name, Kind, _Bound) | Parameters], [Argument | Arguments],
                      EnvironmentIn, EnvironmentOut) :-
  put_assoc(Name, EnvironmentIn, type_parameter_binding(Argument, Kind), Environment1),
  bind_alias_parameters(Parameters, Arguments, Environment1, EnvironmentOut).

% A tuple type's members become keyed fields: positional members get
% sequential `index` keys, labeled members get `label` keys.
convert_members([], _Index, _Environment, _Expanding, _Level, Context, [], Context).
convert_members([tuple_type_member(Mutability, Label, TypeExpression) | Members], Index,
                Environment, Expanding, Level, ContextIn,
                [tuple_field(Mutability, Key, Type) | Fields], ContextOut) :-
  type_member_key(Label, Index, Key, NextIndex),
  convert_proper(TypeExpression, Environment, Expanding, Level, ContextIn, Type, Context1),
  convert_members(Members, NextIndex, Environment, Expanding, Level, Context1, Fields, ContextOut).

type_member_key(positional, Index, index(Index), NextIndex) :-
  NextIndex is Index + 1.
type_member_key(labeled(Name), Index, label(Name), Index).

require_no_arguments(_, []) :- !.
require_no_arguments(Name, _) :-
  throw(analysis_error(type_not_parameterized(Name))).

builtin_type("number", number).
builtin_type("boolean", boolean).
builtin_type("string", string).

parameter_names([], []).
parameter_names([type_parameter(Name, _Kind, _Bound) | Parameters], [Name | Names]) :-
  parameter_names(Parameters, Names).

has_duplicate([Element | Rest]) :-
  ( memberchk(Element, Rest) -> true ; has_duplicate(Rest) ).
