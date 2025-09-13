:- module(binary, [infer_binary/7]).

:- use_module(library(lists)).

:- use_module('../type', [fresh_type_variable/3]).

:- meta_predicate(infer_binary(4, ?, ?, ?, ?, ?, ?)).

infer_binary(
  InferFunctor,
  Operator,
  LeftExpression,
  RightExpression,
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
    LeftExpression,
    InferenceState1,
    InferenceState2,
    inferred(
      Assumptions1,
      Constraints1,
      LeftExpressionType
    )
  ),
  call(
    InferFunctor,
    RightExpression,
    InferenceState2,
    InferenceState3,
    inferred(
      Assumptions2,
      Constraints2,
      RightExpressionType
    )
  ),
  append(Assumptions1, Assumptions2, Assumptions),
  expected_type_for_operator(
    Operator,
    OperatorType,
    InferenceState3,
    NextInferenceState,
    Constraints3
  ),
  append(
    [
      Constraints1,
      Constraints2,
      Constraints3,
      [subsumption_constraint(
        type_arrow(LeftExpressionType, type_arrow(RightExpressionType, Type)),
        OperatorType
      )]
    ],
    Constraints
  ).

expected_type_for_operator(
  binary_operator(multiplication),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(number))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(division),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(number))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(addition),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(number))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(subtraction),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(number))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(left_bit_shift),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(number))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(right_bit_shift),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(number))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(less_than_or_equal),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(boolean))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(less_than),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(boolean))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(greater_than_or_equal),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(boolean))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(greater_than),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(boolean))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(equal),
  type_arrow(TypeLeft, type_arrow(TypeRight, type_constant(boolean))),
  InferenceState,
  NextInferenceState,
  [
    subsumption_constraint(TypeLeft, Type),
    subsumption_constraint(TypeRight, Type)
  ]
) :-
  fresh_type_variable(InferenceState, InferenceState1, TypeLeft),
  fresh_type_variable(InferenceState1, InferenceState2, TypeRight),
  fresh_type_variable(InferenceState2, NextInferenceState, Type).
expected_type_for_operator(
  binary_operator(not_equal),
  type_arrow(TypeLeft, type_arrow(TypeRight, type_constant(boolean))),
  InferenceState,
  NextInferenceState,
  [
    subsumption_constraint(TypeLeft, Type),
    subsumption_constraint(TypeRight, Type)
  ]
) :-
  fresh_type_variable(InferenceState, InferenceState1, TypeLeft),
  fresh_type_variable(InferenceState1, InferenceState2, TypeRight),
  fresh_type_variable(InferenceState2, NextInferenceState, Type).
expected_type_for_operator(
  binary_operator(and),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(number))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(xor),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(number))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(or),
  type_arrow(type_constant(number), type_arrow(type_constant(number), type_constant(number))),
  InferenceState,
  InferenceState,
  []
).
expected_type_for_operator(
  binary_operator(pipe),
  type_arrow(ValueType, type_arrow(ParameterType, ReturnType)),
  InferenceState,
  NextInferenceState,
  [
    subsumption_constraint(ValueType, ParameterType)
  ]
) :-
  fresh_type_variable(InferenceState, InferenceState1, ValueType),
  fresh_type_variable(InferenceState1, InferenceState2, ParameterType),
  fresh_type_variable(InferenceState2, NextInferenceState, ReturnType).
