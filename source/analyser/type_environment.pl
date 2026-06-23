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
  convert_type(Body, ValidationEnvironment, [Name], 0, Context1, _Validated, _Context2),
  validate_declarations(Rest, TypeEnvironment).

validate_constructor_fields([], _Environment, _Context).
validate_constructor_fields([constructor(_Name, FieldTypes) | Rest], Environment, ContextIn) :-
  convert_field_types(FieldTypes, Environment, 0, ContextIn, _ConvertedFields, Context1),
  validate_constructor_fields(Rest, Environment, Context1).

% Convert a constructor's positional field type expressions in order.
convert_field_types([], _Environment, _Level, Context, [], Context).
convert_field_types([FieldExpression | Rest], Environment, Level, ContextIn, [FieldType | FieldTypes], ContextOut) :-
  convert_type(FieldExpression, Environment, [], Level, ContextIn, FieldType, Context1),
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
quantified_parameter_scope([type_parameter(Name, _Bound) | Rest], Index, EnvironmentIn, EnvironmentOut,
                           [quantified_variable(Index) | Variables], [Index | Ids]) :-
  put_assoc(Name, EnvironmentIn, type_parameter_binding(quantified_variable(Index)), Environment1),
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
fresh_parameter_scope([type_parameter(Name, _Bound) | Rest], EnvironmentIn, Level, ContextIn,
                      EnvironmentOut, [Fresh | Variables], ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Fresh, Context1),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(Fresh), Environment1),
  fresh_parameter_scope(Rest, Environment1, Level, Context1, EnvironmentOut, Variables, ContextOut).

%% union_constructor_names(+UnionName, +TypeEnvironment, -Names).
union_constructor_names(UnionName, TypeEnvironment, Names) :-
  get_assoc(UnionName, TypeEnvironment, type_variant_info(_Parameters, Constructors)),
  findall(Name, member(constructor(Name, _Fields), Constructors), Names).

% Bind each parameter to a fresh placeholder for validation, after checking
% its bound is itself well-formed.
bind_validation_parameters([], Environment, Context, Environment, Context).
bind_validation_parameters([type_parameter(Name, Bound) | Rest], EnvironmentIn, ContextIn,
                           EnvironmentOut, ContextOut) :-
  validate_bound(Bound, EnvironmentIn, ContextIn, Context1),
  fresh_unification_variable(Context1, 0, Placeholder, Context2),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(Placeholder), Environment1),
  bind_validation_parameters(Rest, Environment1, Context2, EnvironmentOut, ContextOut).

validate_bound(no_bound, _Environment, Context, Context).
validate_bound(bound(BoundExpression), Environment, ContextIn, ContextOut) :-
  convert_type(BoundExpression, Environment, [], 0, ContextIn, _BoundType, ContextOut).

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
bind_type_parameters([type_parameter(Name, Bound) | Rest], EnvironmentIn, Level, ContextIn,
                     EnvironmentOut, ContextOut) :-
  parameter_monotype(Bound, EnvironmentIn, Level, ContextIn, MonoType, Context1),
  put_assoc(Name, EnvironmentIn, type_parameter_binding(MonoType), Environment1),
  bind_type_parameters(Rest, Environment1, Level, Context1, EnvironmentOut, ContextOut).

parameter_monotype(no_bound, _Environment, Level, ContextIn, MonoType, ContextOut) :-
  fresh_unification_variable(ContextIn, Level, MonoType, ContextOut).
parameter_monotype(bound(BoundExpression), Environment, Level, ContextIn, MonoType, ContextOut) :-
  convert_type(BoundExpression, Environment, [], Level, ContextIn, MonoType, ContextOut).

% ---------------------------------------------------------------------------
% Converting surface type expressions to monotypes
% ---------------------------------------------------------------------------

%% convert_annotation_type(+TypeExpression, +TypeEnvironment, +Level, +ContextIn, -MonoType, -ContextOut).
convert_annotation_type(TypeExpression, TypeEnvironment, Level, ContextIn, MonoType, ContextOut) :-
  convert_type(TypeExpression, TypeEnvironment, [], Level, ContextIn, MonoType, ContextOut).

% convert_type(+TypeExpression, +Environment, +Expanding, +Level, +ContextIn, -MonoType, -ContextOut).
convert_type(tuple_type_node(Members, Openness), Environment, Expanding, Level, ContextIn,
             tuple_type(Fields, Tail), ContextOut) :- !,
  convert_members(Members, 0, Environment, Expanding, Level, ContextIn, Fields, Context1),
  tail_for(Openness, Environment, Level, Context1, Tail, ContextOut).
convert_type(function_type_node(Parameters, Return), Environment, Expanding, Level, ContextIn,
             function_type(ParameterTypes, ReturnType), ContextOut) :- !,
  convert_each(Parameters, Environment, Expanding, Level, ContextIn, ParameterTypes, Context1),
  convert_type(Return, Environment, Expanding, Level, Context1, ReturnType, ContextOut).
convert_type(type_name_node(Name, Arguments), Environment, Expanding, Level, ContextIn,
             MonoType, ContextOut) :-
  ( builtin_type(Name, BaseType) ->
      require_no_arguments(Name, Arguments),
      MonoType = BaseType,
      ContextOut = ContextIn
  ; get_assoc(Name, Environment, Entry) ->
      convert_named(Entry, Name, Arguments, Environment, Expanding, Level, ContextIn, MonoType, ContextOut)
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
  ( get_assoc(Name, Environment, type_parameter_binding(Tail)) ->
      true
  ; throw(analysis_error(undeclared_row_variable(Name)))
  ).

% A name bound to a type parameter is nullary and resolves to its monotype.
convert_named(type_parameter_binding(MonoType), Name, Arguments, _Environment, _Expanding,
              _Level, Context, MonoType, Context) :-
  require_no_arguments(Name, Arguments).
% A tagged-union type is NOMINAL: a reference becomes `type_constructor`.
convert_named(type_variant_info(Parameters, _Constructors), Name, Arguments, Environment,
              Expanding, Level, ContextIn, type_constructor(Name, ArgumentTypes), ContextOut) :-
  check_arity(Name, Parameters, Arguments),
  convert_each(Arguments, Environment, Expanding, Level, ContextIn, ArgumentTypes, Context1),
  enforce_bounds(Parameters, ArgumentTypes, Environment, Level, Context1, ContextOut).
% A declared type: check arity, convert arguments, enforce bounds, then
% either build a nominal constructor (opaque) or expand the body (transparent).
convert_named(type_declaration_info(Opacity, Parameters, Body), Name, Arguments, Environment,
              Expanding, Level, ContextIn, MonoType, ContextOut) :-
  check_arity(Name, Parameters, Arguments),
  convert_each(Arguments, Environment, Expanding, Level, ContextIn, ArgumentTypes, Context1),
  enforce_bounds(Parameters, ArgumentTypes, Environment, Level, Context1, Context2),
  resolve_declared(Opacity, Name, Parameters, Body, ArgumentTypes, Environment, Expanding, Level,
                   Context2, MonoType, ContextOut).

enforce_bounds([], [], _Environment, _Level, Context, Context).
enforce_bounds([type_parameter(_, no_bound) | Parameters], [_Argument | Arguments], Environment,
               Level, ContextIn, ContextOut) :-
  enforce_bounds(Parameters, Arguments, Environment, Level, ContextIn, ContextOut).
enforce_bounds([type_parameter(_, bound(BoundExpression)) | Parameters], [Argument | Arguments],
               Environment, Level, ContextIn, ContextOut) :-
  convert_type(BoundExpression, Environment, [], Level, ContextIn, BoundType, Context1),
  unify(Argument, BoundType, Context1, Context2),
  enforce_bounds(Parameters, Arguments, Environment, Level, Context2, ContextOut).

resolve_declared(opaque, Name, _Parameters, _Body, ArgumentTypes, _Environment, _Expanding,
                 _Level, Context, type_constructor(Name, ArgumentTypes), Context).
resolve_declared(transparent, Name, Parameters, Body, ArgumentTypes, Environment, Expanding,
                 Level, ContextIn, MonoType, ContextOut) :-
  ( memberchk(Name, Expanding) ->
      throw(analysis_error(cyclic_type_alias(Name)))
  ; true
  ),
  bind_alias_parameters(Parameters, ArgumentTypes, Environment, BodyEnvironment),
  convert_type(Body, BodyEnvironment, [Name | Expanding], Level, ContextIn, MonoType, ContextOut).

bind_alias_parameters([], [], Environment, Environment).
bind_alias_parameters([type_parameter(Name, _) | Parameters], [Argument | Arguments],
                      EnvironmentIn, EnvironmentOut) :-
  put_assoc(Name, EnvironmentIn, type_parameter_binding(Argument), Environment1),
  bind_alias_parameters(Parameters, Arguments, Environment1, EnvironmentOut).

% A tuple type's members become keyed fields: positional members get
% sequential `index` keys, labeled members get `label` keys.
convert_members([], _Index, _Environment, _Expanding, _Level, Context, [], Context).
convert_members([tuple_type_member(Mutability, Label, TypeExpression) | Members], Index,
                Environment, Expanding, Level, ContextIn,
                [tuple_field(Mutability, Key, Type) | Fields], ContextOut) :-
  type_member_key(Label, Index, Key, NextIndex),
  convert_type(TypeExpression, Environment, Expanding, Level, ContextIn, Type, Context1),
  convert_members(Members, NextIndex, Environment, Expanding, Level, Context1, Fields, ContextOut).

type_member_key(positional, Index, index(Index), NextIndex) :-
  NextIndex is Index + 1.
type_member_key(labeled(Name), Index, label(Name), Index).

convert_each([], _Environment, _Expanding, _Level, Context, [], Context).
convert_each([TypeExpression | Rest], Environment, Expanding, Level, ContextIn,
             [MonoType | MonoTypes], ContextOut) :-
  convert_type(TypeExpression, Environment, Expanding, Level, ContextIn, MonoType, Context1),
  convert_each(Rest, Environment, Expanding, Level, Context1, MonoTypes, ContextOut).

require_no_arguments(_, []) :- !.
require_no_arguments(Name, _) :-
  throw(analysis_error(type_not_parameterized(Name))).

check_arity(Name, Parameters, Arguments) :-
  length(Parameters, Expected),
  length(Arguments, Given),
  ( Expected =:= Given ->
      true
  ; throw(analysis_error(type_constructor_arity_mismatch(Name, Expected, Given)))
  ).

builtin_type("number", number).
builtin_type("boolean", boolean).
builtin_type("string", string).

parameter_names([], []).
parameter_names([type_parameter(Name, _) | Parameters], [Name | Names]) :-
  parameter_names(Parameters, Names).

has_duplicate([Element | Rest]) :-
  ( memberchk(Element, Rest) -> true ; has_duplicate(Rest) ).
