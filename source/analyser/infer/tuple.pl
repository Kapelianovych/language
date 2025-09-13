:- module(tuple, [infer_tuple/5]).

:- use_module(library(lists)).

:- meta_predicate(infer_tuple(4, ?, ?, ?, ?)).

infer_tuple(
  InferFunctor,
  Expressions,
  InferenceState,
  NextInferenceState,
  inferred(
    Assumptions,
    Constraints,
    type_constant(tuple(Members))
  )
) :-
  infer_tuple_members(
    InferFunctor,
    Expressions,
    InferenceState,
    NextInferenceState,
    inferred(
      Assumptions,
      Constraints,
      Members
    )
  ).

infer_tuple_members(
  _,
  [],
  InferenceState,
  InferenceState,
  inferred(
    [],
    [],
    []
  )
).
infer_tuple_members(
  InferFunctor,
  [Expression | Expressions],
  InferenceState,
  NextInferenceState,
  inferred(
    Assumptions,
    Constraints,
    [Type | Types]
  )
) :-
  call(
    InferFunctor,
    Expression,
    InferenceState,
    IntermediateInferenceState,
    inferred(
      IntermediateAssumptions,
      IntermediateConstraints,
      Type
    )
  ),
  infer_tuple_members(
    InferFunctor,
    Expressions,
    IntermediateInferenceState,
    NextInferenceState,
    inferred(
      RestAssumptions,
      RestConstraints,
      Types
    )
  ),
  append(IntermediateAssumptions, RestAssumptions, Assumptions),
  append(IntermediateConstraints, RestConstraints, Constraints).
