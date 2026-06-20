:- module(infer, [
  infer_program/3,
  infer/7
]).

/*  infer.pl  --  The level-indexed inference judgement.

    This module walks the parser's AST and computes a type for every
    expression, threading the algorithmic context of `types.pl`.  It is a
    synthesis-only ("Algorithm W"-style) presentation of the level-based
    rules from Fan, Xu & Xie (PLDI'25); since the source language has no
    type annotations, the bidirectional *checking* mode of the paper is
    never triggered, so a single inference judgement suffices.

    The central judgement is

        infer(+Node, +Level, +InFunction, +Env, +CtxIn, -Type, -CtxOut)

    read as:  under term environment `Env`, at typing level `Level`, the
    expression `Node` synthesises type `Type`, taking the algorithmic
    context from `CtxIn` to `CtxOut`.

    `Env` is the term context `Sigma`: an assoc from a variable name (the
    identifier's character list) to a tagged binding

        defined(Scheme)    -- a name that is fully in scope and usable
                              anywhere (a parameter, an outer binding, or
                              an already-processed definition).
        forward(Scheme)    -- a name whose definition appears *later* in
                              the current sequence; it is a placeholder
                              that may only be referenced from *inside a
                              function body*.

    `InFunction` (a boolean) records whether we are currently underneath a
    lambda.  It gates forward references: a function may call another
    function defined later, but a value cannot refer forward to a name
    that has not yet been defined (see the identifier rule).

    --------------------------------------------------------------------
    LEVELS AND SCOPES
    --------------------------------------------------------------------
    The typing level tracks nesting depth.  The only construct that
    increments it is a *definition* (`x = e`), this language's `let`: we
    type the right-hand side one level deeper and then generalise (see
    infer_sequence/6).  Lambdas keep the level fixed and introduce
    monomorphic parameters (rule LT-LAM), exactly as in HM.
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).

:- use_module(types, [
  fresh_uvar/4,
  resolve/3,
  unify/4,
  generalize/5,
  instantiate/5,
  monomorphic_scheme/2
]).
:- use_module(operators, [
  unary_signature/4,
  binary_signature/7
]).

%% infer_program(+ProgramNode, +CtxIn, -Result).
%
% Entry point for a whole program.  A program is a sequence of top-level
% expressions evaluated at level 0; top-level definitions are let-bound
% (and generalised) for the remainder of the program.  Forward references
% between top-level functions are allowed (the sequence pre-binds every
% definition name), but a forward reference outside a function body is
% rejected.  `Result` is `program_type(LastType, CtxOut)`.
infer_program(program_node(Expressions), CtxIn, program_type(LastType, CtxOut)) :-
  empty_assoc(Env),
  infer_sequence(Expressions, 0, false, Env, CtxIn, LastType, CtxOut).

% ---------------------------------------------------------------------------
% Sequences: programs and blocks  (this is where `let` lives)
% ---------------------------------------------------------------------------

%% infer_sequence(+Expressions, +Level, +InFunction, +Env, +CtxIn, -ResultType, -CtxOut).
%
% A sequence is the scope shared by a group of definitions.  Two things
% happen here:
%
%   1. PRE-BINDING (forward references).  Before typing anything we give
%      every definition name in the sequence a fresh placeholder variable
%      at the *outer* level and bind it as `forward(...)`.  This makes the
%      name resolvable from earlier definitions -- but, being `forward`,
%      only from inside a function body.  Placing the placeholder at the
%      outer level is deliberate: if a forward reference is taken, the
%      level machinery keeps the whole recursive group monomorphic (ML-
%      style `let rec`), which is what makes generalising it sound.
%
%   2. LEFT-TO-RIGHT PROCESSING (let-generalisation).  We then walk the
%      sequence.  A definition `x = e` is typed one level deeper and then
%      generalised over the variables that remained at that deeper level
%      (rule LT-LET's `ftv^{n+1}`), after which `x` is rebound as
%      `defined(Scheme)` for the rest of the sequence.  An *independent*
%      definition (never referenced forward) keeps its placeholder unused
%      and is generalised fully, so ordinary let-polymorphism still holds.
%
% Only the type of the *last* element is reported; an empty sequence has
% the unit type `()`.
infer_sequence(Expressions, Level, InFunction, Env, CtxIn, ResultType, CtxOut) :-
  definition_names(Expressions, Names),
  prebind_forward(Names, Level, Env, CtxIn, Env1, Ctx1),
  infer_sequence_walk(Expressions, Level, InFunction, Env1, Ctx1, ResultType, CtxOut).

% Collect the names bound by definitions directly in this sequence.
definition_names([], []).
definition_names([definition_node(identifier_node(Name), _) | Es], [Name | Names]) :- !,
  definition_names(Es, Names).
definition_names([_ | Es], Names) :-
  definition_names(Es, Names).

% Bind each name to a fresh placeholder variable, tagged `forward`.
prebind_forward([], _Level, Env, Ctx, Env, Ctx).
prebind_forward([Name | Names], Level, Env, CtxIn, EnvOut, CtxOut) :-
  fresh_uvar(CtxIn, Level, Placeholder, Ctx1),
  monomorphic_scheme(Placeholder, Scheme),
  put_assoc(Name, Env, forward(Scheme), Env1),
  prebind_forward(Names, Level, Env1, Ctx1, EnvOut, CtxOut).

% Walk the sequence, threading the (growing) environment and reporting the
% last expression's type.
infer_sequence_walk([], _Level, _InFunction, _Env, Ctx, tuple_type([]), Ctx).
infer_sequence_walk([Expression], Level, InFunction, Env, CtxIn, ResultType, CtxOut) :-
  infer_sequence_item(Expression, Level, InFunction, Env, CtxIn, ResultType, _Env1, CtxOut).
infer_sequence_walk([Expression, Next | Rest], Level, InFunction, Env, CtxIn, ResultType, CtxOut) :-
  infer_sequence_item(Expression, Level, InFunction, Env, CtxIn, _Type, Env1, Ctx1),
  infer_sequence_walk([Next | Rest], Level, InFunction, Env1, Ctx1, ResultType, CtxOut).

% Process one sequence element, returning its type and the environment to
% use for the rest of the sequence.
infer_sequence_item(definition_node(identifier_node(Name), Value),
                    Level, InFunction, Env, CtxIn, ValueType, EnvOut, CtxOut) :- !,
  Level1 is Level + 1,
  infer(Value, Level1, InFunction, Env, CtxIn, ValueType, Ctx1),
  tie_forward_knot(Name, Env, ValueType, Ctx1, Ctx2),
  generalize(ValueType, Level, Ctx2, Scheme, Ctx3),
  put_assoc(Name, Env, defined(Scheme), EnvOut),
  CtxOut = Ctx3.
infer_sequence_item(Expression, Level, InFunction, Env, CtxIn, Type, Env, CtxOut) :-
  infer(Expression, Level, InFunction, Env, CtxIn, Type, CtxOut).

% If this definition's name was referenced forward (so its placeholder has
% already been solved during an earlier definition), unify the placeholder
% with the value's type to close the recursive loop.  If it was never
% referenced, the placeholder is left untouched so the definition can be
% generalised independently.
tie_forward_knot(Name, Env, ValueType, CtxIn, CtxOut) :-
  get_assoc(Name, Env, forward(scheme([], Placeholder))),
  ( placeholder_referenced(Placeholder, CtxIn) ->
      unify(ValueType, Placeholder, CtxIn, CtxOut)
  ; CtxOut = CtxIn
  ).

% A placeholder counts as "referenced" once it has been solved, which only
% happens when an earlier (or self-) reference unified against it.
placeholder_referenced(Placeholder, Ctx) :-
  resolve(Placeholder, Ctx, Resolved),
  Resolved \= Placeholder.

% ---------------------------------------------------------------------------
% The per-node inference rules
% ---------------------------------------------------------------------------

% Literals (rules LT-LIT and friends): a constant base type, context
% unchanged.
infer(number_node(_), _Level, _InFunction, _Env, Ctx, number, Ctx).
infer(boolean_node(_), _Level, _InFunction, _Env, Ctx, boolean, Ctx).

% String literal: the result is `string`, but each interpolated
% `{ expr }` must itself be well-typed, so we still infer through it.
infer(string_node(Parts), Level, InFunction, Env, CtxIn, string, CtxOut) :-
  infer_string_parts(Parts, Level, InFunction, Env, CtxIn, CtxOut).

% Variable (rule LT-VAR): look the name up and instantiate its scheme with
% fresh variables at the current level.  A `forward` binding may only be
% used inside a function body.
infer(identifier_node(Name), Level, InFunction, Env, CtxIn, Type, CtxOut) :-
  ( get_assoc(Name, Env, Binding) ->
      binding_scheme(Binding, InFunction, Name, Scheme),
      instantiate(Scheme, Level, CtxIn, Type, CtxOut)
  ; throw(analysis_error(unbound_variable(Name)))
  ).

% Lambda (rule LT-LAM): each parameter gets a fresh *monomorphic* variable
% at the current level; the body is typed with those bound and with
% `InFunction = true`, which is what licenses forward references inside it.
infer(function_node(Parameters, Body), Level, _InFunction, Env, CtxIn,
     function_type(ParamTypes, BodyType), CtxOut) :-
  bind_parameters(Parameters, Level, Env, CtxIn, ParamTypes, Env1, Ctx1),
  infer(Body, Level, true, Env1, Ctx1, BodyType, CtxOut).

% Tuple: infer each component; the type is the tuple of their types.
infer(tuple_node(Elements), Level, InFunction, Env, CtxIn, tuple_type(ElementTypes), CtxOut) :-
  infer_each(Elements, Level, InFunction, Env, CtxIn, ElementTypes, CtxOut).

% Block: its own lexical scope, behaving like a sequence.  Inner
% definitions are local to the block and do not leak out.
infer(block_node(Expressions), Level, InFunction, Env, CtxIn, Type, CtxOut) :-
  infer_sequence(Expressions, Level, InFunction, Env, CtxIn, Type, CtxOut).

% Application (rule LT-APP / AT-APP), with partial application: infer the
% callee and the arguments, then feed the arguments to the callee via
% apply_function/6, which honours the callee's known arity.
infer(function_call_node(Target, Arguments), Level, InFunction, Env, CtxIn, ResultType, CtxOut) :-
  infer(Target, Level, InFunction, Env, CtxIn, TargetType, Ctx1),
  infer_each(Arguments, Level, InFunction, Env, Ctx1, ArgumentTypes, Ctx2),
  apply_function(TargetType, ArgumentTypes, Level, Ctx2, ResultType, CtxOut).

% Conditional: the condition must be boolean and the two branches must
% agree; the result is their common type.
infer(conditional_node(Condition, Then, Else), Level, InFunction, Env, CtxIn, BranchType, CtxOut) :-
  infer(Condition, Level, InFunction, Env, CtxIn, ConditionType, Ctx1),
  unify(ConditionType, boolean, Ctx1, Ctx2),
  infer(Then, Level, InFunction, Env, Ctx2, BranchType, Ctx3),
  infer(Else, Level, InFunction, Env, Ctx3, ElseType, Ctx4),
  unify(BranchType, ElseType, Ctx4, CtxOut).

% Unary operator: unify the operand against the operator's expected type.
infer(unary_node(Operator, Operand), Level, InFunction, Env, CtxIn, ResultType, CtxOut) :-
  unary_signature(Operator, Level, OperandType, ResultType),
  infer(Operand, Level, InFunction, Env, CtxIn, ActualOperandType, Ctx1),
  unify(ActualOperandType, OperandType, Ctx1, CtxOut).

% Binary operator: infer both operands, fetch the operator signature
% (which may introduce fresh variables for the polymorphic operators),
% and unify.
infer(binary_node(Operator, Left, Right), Level, InFunction, Env, CtxIn, ResultType, CtxOut) :-
  infer(Left, Level, InFunction, Env, CtxIn, LeftActual, Ctx1),
  infer(Right, Level, InFunction, Env, Ctx1, RightActual, Ctx2),
  binary_signature(Operator, Level, Ctx2, LeftExpected, RightExpected, ResultType, Ctx3),
  unify(LeftActual, LeftExpected, Ctx3, Ctx4),
  unify(RightActual, RightExpected, Ctx4, CtxOut).

% A definition reached *outside* a sequence position (e.g. as a function
% argument): it cannot bind anything visible, so it just contributes the
% type of its value.
infer(definition_node(_Target, Value), Level, InFunction, Env, CtxIn, ValueType, CtxOut) :-
  infer(Value, Level, InFunction, Env, CtxIn, ValueType, CtxOut).

% ---------------------------------------------------------------------------
% Application, with partial application
% ---------------------------------------------------------------------------

%% apply_function(+TargetType, +ArgTypes, +Level, +CtxIn, -ResultType, -CtxOut).
%
% Apply a callee of type `TargetType` to the argument types `ArgTypes`.
%
%   * If the callee's arity is known (it resolves to a `function_type`):
%       - exactly enough arguments      -> the return type;
%       - fewer arguments (k < n)       -> PARTIAL APPLICATION: a function
%         of the remaining parameters, e.g. applying `(number number) ->
%         number` to one `number` yields `(number) -> number`;
%       - more arguments (k > n)        -> apply the first n, then treat
%         the return type as a new callee for the rest (over-application).
%
%   * If the callee is still an unknown unification variable, its arity is
%     unknown, so we fall back to full application: unify it with
%     `(args) -> result` for a fresh `result`.
%
%   * Otherwise (a non-function such as `number`) unification reports the
%     "not a function" clash.
apply_function(TargetType, ArgTypes, Level, CtxIn, ResultType, CtxOut) :-
  resolve(TargetType, CtxIn, Resolved),
  ( Resolved = function_type(Params, Ret) ->
      apply_known(Params, Ret, ArgTypes, Level, CtxIn, ResultType, CtxOut)
  ; Resolved = uvar(_) ->
      fresh_uvar(CtxIn, Level, Result, Ctx1),
      unify(Resolved, function_type(ArgTypes, Result), Ctx1, CtxOut),
      ResultType = Result
  ; % Not a function: let unify produce the clash message.
    fresh_uvar(CtxIn, Level, Result, Ctx1),
    unify(Resolved, function_type(ArgTypes, Result), Ctx1, CtxOut),
    ResultType = Result
  ).

% Apply a callee whose parameter list `Params` is known.
apply_known(Params, Ret, ArgTypes, Level, CtxIn, ResultType, CtxOut) :-
  length(Params, ParamCount),
  length(ArgTypes, ArgCount),
  ( ArgCount =< ParamCount ->
      % Exact or partial application.
      length(Used, ArgCount),
      append(Used, Remaining, Params),
      unify_pairs(ArgTypes, Used, CtxIn, CtxOut),
      ( Remaining = [] ->
          ResultType = Ret                        % saturated
      ; ResultType = function_type(Remaining, Ret) % partial: a new function
      )
  ; % Over-application: saturate, then apply the result to the surplus.
    length(Used, ParamCount),
    append(Used, Surplus, ArgTypes),
    unify_pairs(Used, Params, CtxIn, Ctx1),
    apply_function(Ret, Surplus, Level, Ctx1, ResultType, CtxOut)
  ).

unify_pairs([], [], Ctx, Ctx).
unify_pairs([A | As], [B | Bs], CtxIn, CtxOut) :-
  unify(A, B, CtxIn, Ctx1),
  unify_pairs(As, Bs, Ctx1, CtxOut).

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

% Decide which scheme an identifier's binding yields, enforcing that a
% forward reference is only legal inside a function body.
binding_scheme(defined(Scheme), _InFunction, _Name, Scheme).
binding_scheme(forward(Scheme), InFunction, Name, Scheme) :-
  ( InFunction == true ->
      true
  ; throw(analysis_error(forward_reference_outside_function(Name)))
  ).

% Infer a list of expressions left-to-right, collecting their types.
infer_each([], _Level, _InFunction, _Env, Ctx, [], Ctx).
infer_each([E | Es], Level, InFunction, Env, CtxIn, [T | Ts], CtxOut) :-
  infer(E, Level, InFunction, Env, CtxIn, T, Ctx1),
  infer_each(Es, Level, InFunction, Env, Ctx1, Ts, CtxOut).

% Bind lambda parameters to fresh monomorphic variables at `Level`.
bind_parameters([], _Level, Env, Ctx, [], Env, Ctx).
bind_parameters([identifier_node(Name) | Parameters], Level, Env, CtxIn,
               [ParamType | ParamTypes], EnvOut, CtxOut) :-
  fresh_uvar(CtxIn, Level, ParamType, Ctx1),
  monomorphic_scheme(ParamType, Scheme),
  put_assoc(Name, Env, defined(Scheme), Env1),
  bind_parameters(Parameters, Level, Env1, Ctx1, ParamTypes, EnvOut, CtxOut).

% Type-check the interpolated expressions inside a string literal; the
% static character runs carry no type obligation.
infer_string_parts([], _Level, _InFunction, _Env, Ctx, Ctx).
infer_string_parts([string_static_part(_) | Parts], Level, InFunction, Env, CtxIn, CtxOut) :-
  infer_string_parts(Parts, Level, InFunction, Env, CtxIn, CtxOut).
infer_string_parts([string_interpolated_part(Node) | Parts], Level, InFunction, Env, CtxIn, CtxOut) :-
  infer(Node, Level, InFunction, Env, CtxIn, _Type, Ctx1),
  infer_string_parts(Parts, Level, InFunction, Env, Ctx1, CtxOut).
