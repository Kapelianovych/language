:- module(unary, [infer_unary/6]).

:- use_module(library(lists)).

:- use_module('../type', [fresh_type_variable/3]).

:- meta_predicate(infer_unary(4, ?, ?, ?, ?, ?)).

infer_unary(
  InferFunctor,
  Operator,
  Expression,
  InferenceState,
  NextInferenceState,
  inferred(
    Assumptions,
    Constraints,
    Type
  )
) :-
  fresh_type_variable(InferenceState, InferenceState1, Type),
  call(
    InferFunctor,
    Expression,
    InferenceState1,
    NextInferenceState,
    inferred(
      Assumptions,
      Constraints1,
      ExpressionType
    )
  ),
  expected_type_for_operator(Operator, OperatorType),
  append(
    Constraints1,
    [subsumption_constraint(
      type_arrow(ExpressionType, Type),
      OperatorType
    )],
    Constraints
  ).

expected_type_for_operator(
  unary_operator(number_negation),
  type_arrow(type_constant(number), type_constant(number))
).
expected_type_for_operator(
  unary_operator(boolean_negation),
  type_arrow(type_constant(boolean), type_constant(boolean))
).
expected_type_for_operator(
  unary_operator(bit_inversion),
  type_arrow(type_constant(number), type_constant(number))
).
