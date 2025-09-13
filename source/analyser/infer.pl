:- module(infer, [infer/4]).

:- use_module(infer/number, [infer_number/4]).
:- use_module(infer/boolean, [infer_boolean/4]).
:- use_module(infer/string, [infer_string/5]).
:- use_module(infer/function, [infer_function/6]).
:- use_module(infer/tuple, [infer_tuple/5]).
:- use_module(infer/function_call, [infer_function_call/6]).
:- use_module(infer/block, [infer_block/5]).
:- use_module(infer/definition, [infer_definition/6]).
:- use_module(infer/conditional, [infer_conditional/7]).
:- use_module(infer/identifier, [infer_identifier/4]).
:- use_module(infer/unary, [infer_unary/6]).
:- use_module(infer/binary, [infer_binary/7]).

infer(
  number_node(Number),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_number(
    Number,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  boolean_node(Boolean),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_boolean(
    Boolean,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  string_node(Parts),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_string(
    infer,
    Parts,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  function_node(Parameters, Body),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_function(
    infer,
    Parameters,
    Body,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  tuple_node(Expressions),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_tuple(
    infer,
    Expressions,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  function_call_node(Target, Arguments),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_function_call(
    infer,
    Target,
    Arguments,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  block_node(Expressions),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_block(
    infer,
    Expressions,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  definition_node(Name, Expression),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_definition(
    infer,
    Name,
    Expression,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  conditional_node(Condition, ThenBranch, ElseBranch),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_conditional(
    infer,
    Condition,
    ThenBranch,
    ElseBranch,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  identifier_node(Name),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_identifier(
    Name,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  unary_node(Operator, Expression),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_unary(
    infer,
    Operator,
    Expression,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
infer(
  binary_node(Operator, LeftExpression, RightExpression),
  InferenceState,
  NextInferenceState,
  Inferred
) :-
  infer_binary(
    infer,
    Operator,
    LeftExpression,
    RightExpression,
    InferenceState,
    NextInferenceState,
    Inferred
  ).
