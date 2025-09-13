:- module(function_call, [infer_function_call/6]).

:- use_module(library(lists)).

:- use_module('../type', [fresh_type_variable/3,
                          to_type_arrow/3]).

:- meta_predicate(infer_function_call(4, ?, ?, ?, ?, ?)).

infer_function_call(
  InferFunctor,
  Target,
  Arguments,
  InferenceState,
  NextInferenceState,
  inferred(
    Assumptions,
    Constraints,
    Type
  )
) :-
  call(
    InferFunctor,
    Target,
    InferenceState,
    InferenceState1,
    inferred(
      Assumptions1,
      Constraints1,
      TargetType
    )
  ),
  infer_arguments(
    InferFunctor,
    Arguments,
    InferenceState1,
    InferenceState2,
    inferred(
      Assumptions2,
      Constraints2,
      ArgumentTypes
    )
  ),
  fresh_type_variable(InferenceState2, NextInferenceState, Type),
  append(Assumptions1, Assumptions2, Assumptions),
  to_type_arrow(ArgumentTypes, Type, InferredTargetType),
  append(
    [
      Constraints1,
      Constraints2,
      [subsumption_constraint(TargetType, InferredTargetType)]
    ],
    Constraints
  ).

infer_arguments(
  _,
  [],
  InferenceState,
  InferenceState,
  inferred([], [], [])
).
infer_arguments(
  InferFunctor,
  [Argument | Arguments],
  InferenceState,
  NextInferenceState,
  inferred(
    Assumptions,
    Constraints,
    [ArgumentType | ArgumentTypes]
  )
) :-
  call(
    InferFunctor,
    Argument,
    InferenceState,
    InferenceState1,
    inferred(
      Assumptions1,
      Constraints1,
      ArgumentType
    )
  ),
  infer_arguments(
    InferFunctor,
    Arguments,
    InferenceState1,
    NextInferenceState,
    inferred(
      Assumptions2,
      Constraints2,
      ArgumentTypes
    )
  ),
  append(Assumptions1, Assumptions2, Assumptions),
  append(Constraints1, Constraints2, Constraints).
