:- module(conditional, [infer_conditional/7]).

:- use_module(library(lists)).

:- use_module('../type', [fresh_type_variable/3]).

:- meta_predicate(infer_conditional(4, ?, ?, ?, ?, ?, ?)).

infer_conditional(
  InferFunctor,
  Condition,
  ThenBranch,
  ElseBranch,
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
    Condition,
    InferenceState,
    InferenceState1,
    inferred(
      Assumptions1,
      Constraints1,
      ConditionType
    )
  ),
  call(
    InferFunctor,
    ThenBranch,
    InferenceState1,
    InferenceState2,
    inferred(
      Assumptions2,
      Constraints2,
      ThenType
    )
  ),
  call(
    InferFunctor,
    ElseBranch,
    InferenceState2,
    InferenceState3,
    inferred(
      Assumptions3,
      Constraints3,
      ElseType
    )
  ),
  fresh_type_variable(InferenceState3, NextInferenceState, Type),
  append([Assumptions1, Assumptions2, Assumptions3], Assumptions),
  append(
    [
      Constraints1,
      Constraints2,
      Constraints3,
      [
        subsumption_constraint(ConditionType, type_constant(boolean)),
        subsumption_constraint(ThenType, Type),
        subsumption_constraint(ElseType, Type)
      ]
    ],
    Constraints
  ).
