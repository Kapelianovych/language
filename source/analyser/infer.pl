:- module(infer, [
  infer_program/5,
  infer/8
]).

/*  infer.pl  --  The level-indexed inference judgement.

    This module walks the parser's AST and computes a type for every
    expression, threading the algorithmic context of `types.pl`.  It is a
    synthesis-only ("Algorithm W"-style) presentation of the level-based
    rules from Fan, Xu & Xie (PLDI'25).  The source language is mostly
    annotation-free; where an explicit annotation IS written we simply
    unify the inferred type against the annotation.

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
    The typing level tracks nesting depth.  The only construct that
    increments it is a *definition* (`x = e`), this language's `let`.
    Lambdas keep the level fixed and introduce monomorphic parameters.
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).

:- use_module(types, [
  fresh_unification_variable/4,
  resolve_head/3,
  fully_resolve/3,
  unify/4,
  generalize/5,
  instantiate/5,
  monomorphic_type_scheme/2
]).
:- use_module(operators, [
  unary_signature/4,
  binary_signature/7
]).
:- use_module(type_environment, [
  convert_annotation_type/6,
  bind_type_parameters/6,
  instantiate_constructor/7,
  union_constructor_names/3
]).

%% infer_program(+ProgramNode, +TypeEnvironment, +ContextIn, -Result).
%
% Entry point for a whole program: a sequence of top-level expressions
% evaluated at level 0.  `Result` is `program_type(LastType, ContextOut)`.
infer_program(program_node(Expressions), TypeEnvironment, InitialEnvironment, ContextIn,
              program_type(LastType, ContextOut)) :-
  infer_sequence(Expressions, 0, false, InitialEnvironment, TypeEnvironment, ContextIn, LastType, ContextOut).

% ---------------------------------------------------------------------------
% Sequences: programs and blocks  (this is where `let` lives)
% ---------------------------------------------------------------------------

%% infer_sequence(+Expressions, +Level, +InsideFunction, +Environment, +TypeEnvironment, +ContextIn, -ResultType, -ContextOut).
%
% A sequence is the scope shared by a group of definitions.  We first
% pre-bind every definition name as a `forward` placeholder (so earlier
% definitions may refer forward, from inside a function body), then walk
% the sequence left to right, generalising each definition as we pass it.
% Type declarations carry no value and are skipped here (they were already
% collected and validated into `TypeEnvironment`).
infer_sequence(Expressions, Level, InsideFunction, Environment, TypeEnvironment,
               ContextIn, ResultType, ContextOut) :-
  definition_names(Expressions, Names),
  prebind_forward(Names, Level, Environment, ContextIn, Environment1, Context1),
  infer_sequence_walk(Expressions, Level, InsideFunction, Environment1, TypeEnvironment,
                      Context1, ResultType, ContextOut).

% Collect the names bound by value definitions directly in this sequence.
definition_names([], []).
definition_names([definition_node(identifier_node(Name), _, _) | Es], [Name | Names]) :- !,
  definition_names(Es, Names).
definition_names([_ | Es], Names) :-
  definition_names(Es, Names).

% Bind each name to a fresh placeholder variable, tagged `forward`.
prebind_forward([], _Level, Environment, Context, Environment, Context).
prebind_forward([Name | Names], Level, Environment, ContextIn, EnvironmentOut, ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Placeholder, Context1),
  monomorphic_type_scheme(Placeholder, Scheme),
  put_assoc(Name, Environment, forward(Scheme), Environment1),
  prebind_forward(Names, Level, Environment1, Context1, EnvironmentOut, ContextOut).

% Walk the sequence, threading the (growing) environment and reporting the
% last expression's type.  An empty sequence has the unit type `()`.
infer_sequence_walk([], _Level, _InsideFunction, _Environment, _TypeEnvironment,
                    Context, tuple_type([], closed), Context).
infer_sequence_walk([Expression], Level, InsideFunction, Environment, TypeEnvironment,
                    ContextIn, ResultType, ContextOut) :-
  infer_sequence_item(Expression, Level, InsideFunction, Environment, TypeEnvironment,
                      ContextIn, ResultType, _Environment1, ContextOut).
infer_sequence_walk([Expression, Next | Rest], Level, InsideFunction, Environment,
                    TypeEnvironment, ContextIn, ResultType, ContextOut) :-
  infer_sequence_item(Expression, Level, InsideFunction, Environment, TypeEnvironment,
                      ContextIn, _Type, Environment1, Context1),
  infer_sequence_walk([Next | Rest], Level, InsideFunction, Environment1, TypeEnvironment,
                      Context1, ResultType, ContextOut).

% Process one sequence element, returning its type and the environment to
% use for the rest of the sequence.
infer_sequence_item(type_declaration_node(_, _, _, _), _Level, _InsideFunction,
                    Environment, _TypeEnvironment, Context, tuple_type([], closed), Environment, Context) :- !.
% A destructuring definition binds the pattern's variables for the rest of
% the sequence (monomorphically); its value is the matched value's type.
infer_sequence_item(destructuring_node(Pattern, Value), Level, InsideFunction,
                    Environment, TypeEnvironment, ContextIn, ValueType, EnvironmentOut, ContextOut) :- !,
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context1),
  type_pattern(Pattern, ValueType, Level, TypeEnvironment, Environment, Context1, EnvironmentOut, ContextOut).
infer_sequence_item(definition_node(identifier_node(Name), Annotation, Value),
                    Level, InsideFunction, Environment, TypeEnvironment, ContextIn,
                    ValueType, EnvironmentOut, ContextOut) :- !,
  Level1 is Level + 1,
  infer(Value, Level1, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context1),
  apply_annotation(Annotation, ValueType, TypeEnvironment, Level1, Context1, Context2),
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
tie_forward_knot(Name, Environment, ValueType, ContextIn, ContextOut) :-
  get_assoc(Name, Environment, forward(type_scheme([], Placeholder))),
  ( placeholder_referenced(Placeholder, ContextIn) ->
      unify(ValueType, Placeholder, ContextIn, ContextOut)
  ; ContextOut = ContextIn
  ).

placeholder_referenced(Placeholder, Context) :-
  resolve_head(Placeholder, Context, Resolved),
  Resolved \= Placeholder.

% ---------------------------------------------------------------------------
% The per-node inference rules
% ---------------------------------------------------------------------------

% Literals: a constant base type, context unchanged.
infer(number_node(_), _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, number, Context).
infer(boolean_node(_), _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, boolean, Context).

% String literal: the result is `string`, but each interpolated `{ expr }`
% must itself be well-typed, so we still infer through it.
infer(string_node(Parts), Level, InsideFunction, Environment, TypeEnvironment, ContextIn, string, ContextOut) :-
  infer_string_parts(Parts, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ContextOut).

% Variable: look the name up and instantiate its scheme with fresh
% variables at the current level.  A `forward` binding may only be used
% inside a function body.
infer(identifier_node(Name), Level, InsideFunction, Environment, _TypeEnvironment, ContextIn, Type, ContextOut) :-
  ( get_assoc(Name, Environment, Binding) ->
      binding_scheme(Binding, InsideFunction, Name, Scheme),
      instantiate(Scheme, Level, ContextIn, Type, ContextOut)
  ; throw(analysis_error(unbound_variable(Name)))
  ).

% Lambda: each parameter gets a fresh monomorphic variable, constrained by
% its annotation if present; the body is typed with those bound and with
% `InsideFunction = true`.  A return annotation, if present, is unified
% against the inferred body type.
infer(function_node(TypeParameters, Parameters, ReturnAnnotation, Body), Level, _InsideFunction,
      Environment, TypeEnvironment, ContextIn,
      function_type(ParameterTypes, BodyType), ContextOut) :-
  % Explicit generics extend the type environment for this function's
  % parameter / return annotations and body (an unbounded parameter is a
  % fresh variable; a bounded one carries its bound, e.g. an open record).
  bind_type_parameters(TypeParameters, TypeEnvironment, Level, ContextIn, TypeEnvironment1, Context1),
  bind_parameters(Parameters, Level, TypeEnvironment1, Environment, Context1,
                  ParameterTypes, Environment1, Context2),
  infer(Body, Level, true, Environment1, TypeEnvironment1, Context2, BodyType, Context3),
  apply_annotation(ReturnAnnotation, BodyType, TypeEnvironment1, Level, Context3, ContextOut).

% Tuple: infer each member into a field.  A literal is a CLOSED record, so
% its tail is `closed`.  Positional members get sequential `index` keys;
% labeled members get `label` keys.  Labels must be unique.
infer(tuple_node(Members), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, tuple_type(Fields, Tail), ContextOut) :-
  infer_tuple_members(Members, 0, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, Fields, SpreadTypes, ContextOut),
  check_unique_labels(Fields, []),
  spread_tail(SpreadTypes, Tail).

% Block: its own lexical scope, behaving like a sequence.
infer(block_node(Expressions), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, Type, ContextOut) :-
  infer_sequence(Expressions, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, Type, ContextOut).

% Member access `target.label` / `target.index`: constrain the target to be
% a record having AT LEAST this field (an open row tail), with any
% mutability.  The open tail is what makes `(p) p.x` row-polymorphic: the
% target need not be a fully known tuple.
infer(access_node(Target, Accessor), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, FieldType, ContextOut) :-
  infer(Target, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, TargetType, Context1),
  accessor_key(Accessor, Key),
  fresh_unification_variable(Context1, Level, FieldType, Context2),
  fresh_unification_variable(Context2, Level, AnyMutability, Context3),
  fresh_unification_variable(Context3, Level, RestTail, Context4),
  unify(TargetType, tuple_type([tuple_field(AnyMutability, Key, FieldType)], RestTail), Context4, ContextOut).

% Member assignment `target.member = value`: like access, but the member's
% mutability is required to be `mutable`, and the value's type must match.
infer(assignment_node(access_node(Target, Accessor), Value), Level, InsideFunction,
      Environment, TypeEnvironment, ContextIn, ValueType, ContextOut) :-
  infer(Target, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, TargetType, Context1),
  accessor_key(Accessor, Key),
  fresh_unification_variable(Context1, Level, FieldType, Context2),
  fresh_unification_variable(Context2, Level, RestTail, Context3),
  unify(TargetType, tuple_type([tuple_field(mutable, Key, FieldType)], RestTail), Context3, Context4),
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, Context4, ValueType, Context5),
  unify(ValueType, FieldType, Context5, ContextOut).

% Match: the scrutinee's type must satisfy every arm's pattern, each guard
% must be boolean, and every arm's result has the match's (shared) type.
% Patterns are type-consistent with the scrutinee -- there are no union
% types, so all arms describe the same scrutinee type.
infer(match_node(Scrutinee, RawArms), Level, InsideFunction, Environment, TypeEnvironment,
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
infer(destructuring_node(Pattern, Value), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, ValueType, ContextOut) :-
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context1),
  type_pattern(Pattern, ValueType, Level, TypeEnvironment, Environment, Context1, _DiscardedEnvironment, ContextOut).

% Application, with partial application and argument PLACEHOLDERS.  A `_`
% argument is a hole: the call is applied to all positions (holes as fresh
% variables), and the whole expression becomes a function awaiting the holes,
% in order.  With no holes this is ordinary application.
infer(function_call_node(Target, Arguments), Level, InsideFunction, Environment,
      TypeEnvironment, ContextIn, ResultType, ContextOut) :-
  infer(Target, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, TargetType, Context1),
  infer_call_arguments(Arguments, Level, InsideFunction, Environment, TypeEnvironment, Context1, ArgumentTypes, HoleTypes, Context2),
  apply_function(TargetType, ArgumentTypes, Level, Context2, AppliedType, Context3),
  section_result(HoleTypes, AppliedType, ResultType),
  ContextOut = Context3.

% Conditional: the condition must be boolean and the two branches must agree.
infer(conditional_node(Condition, Then, Else), Level, InsideFunction, Environment,
      TypeEnvironment, ContextIn, BranchType, ContextOut) :-
  infer(Condition, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ConditionType, Context1),
  unify(ConditionType, boolean, Context1, Context2),
  infer(Then, Level, InsideFunction, Environment, TypeEnvironment, Context2, BranchType, Context3),
  infer(Else, Level, InsideFunction, Environment, TypeEnvironment, Context3, ElseType, Context4),
  unify(BranchType, ElseType, Context4, ContextOut).

% Unary operator.
infer(unary_node(Operator, Operand), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, ResultType, ContextOut) :-
  unary_signature(Operator, Level, OperandType, ResultType),
  infer(Operand, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ActualOperandType, Context1),
  unify(ActualOperandType, OperandType, Context1, ContextOut).

% Binary operator.
infer(binary_node(Operator, Left, Right), Level, InsideFunction, Environment, TypeEnvironment,
      ContextIn, ResultType, ContextOut) :-
  infer(Left, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, LeftActual, Context1),
  infer(Right, Level, InsideFunction, Environment, TypeEnvironment, Context1, RightActual, Context2),
  binary_signature(Operator, Level, Context2, LeftExpected, RightExpected, ResultType, Context3),
  unify(LeftActual, LeftExpected, Context3, Context4),
  unify(RightActual, RightExpected, Context4, ContextOut).

% A type declaration reached in expression position carries no value.
infer(type_declaration_node(_, _, _, _), _Level, _InsideFunction, _Environment, _TypeEnvironment,
      Context, tuple_type([], closed), Context).

% A definition reached *outside* a sequence position (e.g. as a function
% argument): it cannot bind anything visible, so it just contributes the
% type of its value (still honouring any annotation on it).
infer(definition_node(_Target, Annotation, Value), Level, InsideFunction, Environment,
      TypeEnvironment, ContextIn, ValueType, ContextOut) :-
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context1),
  apply_annotation(Annotation, ValueType, TypeEnvironment, Level, Context1, ContextOut).

% ---------------------------------------------------------------------------
% Annotations
% ---------------------------------------------------------------------------

%% apply_annotation(+Annotation, +InferredType, +TypeEnvironment, +Level, +ContextIn, -ContextOut).
%
% Unify an explicit annotation (if any) against an inferred type.  The
% annotation is converted to a closed monotype via `type_environment.pl`.
apply_annotation(no_annotation, _InferredType, _TypeEnvironment, _Level, Context, Context).
apply_annotation(type_annotation(TypeExpression), InferredType, TypeEnvironment, Level, ContextIn, ContextOut) :-
  convert_annotation_type(TypeExpression, TypeEnvironment, Level, ContextIn, AnnotatedType, Context1),
  unify(AnnotatedType, InferredType, Context1, ContextOut).

% ---------------------------------------------------------------------------
% Application, with partial application
% ---------------------------------------------------------------------------

%% apply_function(+TargetType, +ArgTypes, +Level, +ContextIn, -ResultType, -ContextOut).
apply_function(TargetType, ArgumentTypes, Level, ContextIn, ResultType, ContextOut) :-
  resolve_head(TargetType, ContextIn, Resolved),
  ( Resolved = function_type(Parameters, Return) ->
      apply_known(Parameters, Return, ArgumentTypes, Level, ContextIn, ResultType, ContextOut)
  ; % Unknown callee, or a non-function: let unify settle or report it.
    fresh_unification_variable(ContextIn, Level, Result, Context1),
    unify(Resolved, function_type(ArgumentTypes, Result), Context1, ContextOut),
    ResultType = Result
  ).

% Apply a callee whose parameter list is known: exact, partial, or
% over-application.
apply_known(Parameters, Return, ArgumentTypes, Level, ContextIn, ResultType, ContextOut) :-
  length(Parameters, ParameterCount),
  length(ArgumentTypes, ArgumentCount),
  ( ArgumentCount =< ParameterCount ->
      length(Used, ArgumentCount),
      append(Used, Remaining, Parameters),
      unify_pairs(ArgumentTypes, Used, ContextIn, ContextOut),
      ( Remaining = [] ->
          ResultType = Return
      ; ResultType = function_type(Remaining, Return)
      )
  ; length(Used, ParameterCount),
    append(Used, Surplus, ArgumentTypes),
    unify_pairs(Used, Parameters, ContextIn, Context1),
    apply_function(Return, Surplus, Level, Context1, ResultType, ContextOut)
  ).

unify_pairs([], [], Context, Context).
unify_pairs([A | As], [B | Bs], ContextIn, ContextOut) :-
  unify(A, B, ContextIn, Context1),
  unify_pairs(As, Bs, Context1, ContextOut).

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

% Infer each tuple member into a `tuple_field`.  Positional members are
% assigned sequential `index` keys (skipping labeled members, which keep the
% counter unchanged); labeled members get `label` keys.  Mutability is
% recorded as the base type `readonly` / `mutable`.
infer_tuple_members([], _Index, _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, [], [], Context).
% A spread `..value`: the value must be a record, and its fields are spliced
% in.  We collect its type to use as the new record's tail (see spread_tail).
infer_tuple_members([spread_member(Value) | Members], Index, Level,
                    InsideFunction, Environment, TypeEnvironment, ContextIn,
                    Fields, [SpreadType | SpreadTypes], ContextOut) :-
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, SpreadType, Context1),
  % The spread value must be a record; assert that by unifying it with an
  % open empty record, so spreading a non-record is rejected.
  fresh_unification_variable(Context1, Level, AssertTail, Context2),
  unify(SpreadType, tuple_type([], AssertTail), Context2, Context3),
  infer_tuple_members(Members, Index, Level, InsideFunction, Environment, TypeEnvironment, Context3, Fields, SpreadTypes, ContextOut).
infer_tuple_members([tuple_member(Mutability, Label, Annotation, Value) | Members], Index, Level,
                    InsideFunction, Environment, TypeEnvironment, ContextIn,
                    [tuple_field(Mutability, Key, ValueType) | Fields], SpreadTypes, ContextOut) :-
  member_key(Label, Index, Key, NextIndex),
  infer(Value, Level, InsideFunction, Environment, TypeEnvironment, ContextIn, ValueType, Context1),
  apply_annotation(Annotation, ValueType, TypeEnvironment, Level, Context1, Context2),
  infer_tuple_members(Members, NextIndex, Level, InsideFunction, Environment, TypeEnvironment, Context2, Fields, SpreadTypes, ContextOut).

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

% A member access's surface accessor maps directly to a field key.
accessor_key(label(Name), label(Name)).
accessor_key(index(Index), index(Index)).

% Reject a tuple that labels two members with the same name.
check_unique_labels([], _).
check_unique_labels([tuple_field(_, index(_), _) | Fields], Seen) :-
  check_unique_labels(Fields, Seen).
check_unique_labels([tuple_field(_, label(Name), _) | Fields], Seen) :-
  ( memberchk(Name, Seen) ->
      throw(analysis_error(duplicate_label(Name)))
  ; check_unique_labels(Fields, [Name | Seen])
  ).

% Collect call-argument types in order; a placeholder `_` contributes a fresh
% variable to BOTH the argument list and the (ordered) hole list.
infer_call_arguments([], _Level, _InsideFunction, _Environment, _TypeEnvironment, Context, [], [], Context).
infer_call_arguments([placeholder_node | Arguments], Level, InsideFunction, Environment, TypeEnvironment,
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
bind_parameters([parameter_node(Pattern, Annotation) | Parameters], Level,
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
infer_match_arms([match_arm(Pattern, Guard, Result) | Arms], ScrutineeType, ResultType, Level,
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
desugar_arms([match_arm(Patterns, Guard, Result) | Rest], Arms) :-
  desugar_alternatives(Patterns, Guard, Result, ArmsHead),
  desugar_arms(Rest, ArmsTail),
  append(ArmsHead, ArmsTail, Arms).

desugar_alternatives([], _Guard, _Result, []).
desugar_alternatives([Pattern | Patterns], Guard, Result, [match_arm(Pattern, Guard, Result) | Rest]) :-
  desugar_alternatives(Patterns, Guard, Result, Rest).

% Every alternative of an or-pattern must bind exactly the same set of
% variables, so the shared body sees a consistent binding regardless of which
% alternative matched.
check_or_pattern_bindings([]).
check_or_pattern_bindings([match_arm(Patterns, _Guard, _Result) | Rest]) :-
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
pattern_variables(wildcard_pattern, []).
pattern_variables(binding_pattern(Name), [Name]).
pattern_variables(literal_pattern(_), []).
pattern_variables(constructor_pattern(_Name, SubPatterns), Variables) :-
  patterns_variables(SubPatterns, Variables).
pattern_variables(record_pattern(Members), Variables) :-
  member_patterns_variables(Members, Variables).

patterns_variables([], []).
patterns_variables([Pattern | Patterns], Variables) :-
  pattern_variables(Pattern, Head),
  patterns_variables(Patterns, Tail),
  append(Head, Tail, Variables).

member_patterns_variables([], []).
member_patterns_variables([positional_member_pattern(SubPattern) | Members], Variables) :-
  pattern_variables(SubPattern, Head),
  member_patterns_variables(Members, Tail),
  append(Head, Tail, Variables).
member_patterns_variables([labeled_member_pattern(_Name, SubPattern) | Members], Variables) :-
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

has_catch_all([match_arm(Pattern, no_guard, _Result) | _]) :-
  ( Pattern = wildcard_pattern ; Pattern = binding_pattern(_) ),
  !.
has_catch_all([_ | Arms]) :-
  has_catch_all(Arms).

covered_constructors([], []).
covered_constructors([match_arm(constructor_pattern(Name, _), no_guard, _) | Arms], [Name | Covered]) :- !,
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

%% type_pattern(+Pattern, +ExpectedType, +Level, +TypeEnvironment, +EnvironmentIn, +ContextIn, -EnvironmentOut, -ContextOut).
%
% Constrain `ExpectedType` to match `Pattern`, extending the environment with
% the pattern's bindings (monomorphic).
type_pattern(wildcard_pattern, _ExpectedType, _Level, _TypeEnvironment, Environment, Context, Environment, Context).
type_pattern(binding_pattern(Name), ExpectedType, _Level, _TypeEnvironment, EnvironmentIn, Context, EnvironmentOut, Context) :-
  monomorphic_type_scheme(ExpectedType, Scheme),
  put_assoc(Name, EnvironmentIn, defined(Scheme), EnvironmentOut).
type_pattern(literal_pattern(Node), ExpectedType, _Level, _TypeEnvironment, Environment, ContextIn, Environment, ContextOut) :-
  literal_type(Node, LiteralType),
  unify(ExpectedType, LiteralType, ContextIn, ContextOut).
% A constructor pattern: the scrutinee must be the constructor's union type,
% and each sub-pattern matches the corresponding field type.
type_pattern(constructor_pattern(CtorName, SubPatterns), ExpectedType, Level, TypeEnvironment, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut) :-
  instantiate_constructor(CtorName, TypeEnvironment, Level, ContextIn, UnionType, FieldTypes, Context1),
  ( same_length(SubPatterns, FieldTypes) ->
      true
  ; throw(analysis_error(constructor_pattern_arity_mismatch(CtorName)))
  ),
  unify(ExpectedType, UnionType, Context1, Context2),
  type_pattern_each(SubPatterns, FieldTypes, Level, TypeEnvironment, EnvironmentIn, Context2, EnvironmentOut, ContextOut).
type_pattern(record_pattern(Members), ExpectedType, Level, TypeEnvironment, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut) :-
  type_pattern_members(Members, 0, Level, TypeEnvironment, EnvironmentIn, ContextIn, Fields, EnvironmentOut, Context1),
  unify(ExpectedType, tuple_type(Fields, closed), Context1, ContextOut).

literal_type(number_node(_), number).
literal_type(boolean_node(_), boolean).
literal_type(string_node(_), string).

% Match a list of sub-patterns against a list of (field) types in order.
type_pattern_each([], [], _Level, _TypeEnvironment, Environment, Context, Environment, Context).
type_pattern_each([Pattern | Patterns], [Type | Types], Level, TypeEnvironment, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut) :-
  type_pattern(Pattern, Type, Level, TypeEnvironment, EnvironmentIn, ContextIn, Environment1, Context1),
  type_pattern_each(Patterns, Types, Level, TypeEnvironment, Environment1, Context1, EnvironmentOut, ContextOut).

% Each member contributes a field (with a fresh, don't-care mutability) whose
% type the sub-pattern is then matched against.  Positional members consume an
% index; labeled members do not.  The pattern record is closed (exact).
type_pattern_members([], _Index, _Level, _TypeEnvironment, Environment, Context, [], Environment, Context).
type_pattern_members([positional_member_pattern(SubPattern) | Members], Index, Level, TypeEnvironment, EnvironmentIn, ContextIn,
                     [tuple_field(Mutability, index(Index), FieldType) | Fields], EnvironmentOut, ContextOut) :-
  fresh_unification_variable(ContextIn, Level, Mutability, Context1),
  fresh_unification_variable(Context1, Level, FieldType, Context2),
  type_pattern(SubPattern, FieldType, Level, TypeEnvironment, EnvironmentIn, Context2, Environment1, Context3),
  Index1 is Index + 1,
  type_pattern_members(Members, Index1, Level, TypeEnvironment, Environment1, Context3, Fields, EnvironmentOut, ContextOut).
type_pattern_members([labeled_member_pattern(Name, SubPattern) | Members], Index, Level, TypeEnvironment, EnvironmentIn, ContextIn,
                     [tuple_field(Mutability, label(Name), FieldType) | Fields], EnvironmentOut, ContextOut) :-
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
