:- module(definition, [infer_definition/6]).

:- meta_predicate(infer_definition(4, ?, ?, ?, ?, ?)).

infer_definition(
  InferFunctor,
  Name,
  Value,
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
    Value,
    InferenceState,
    NextInferenceState,
    inferred(
      Assumptions,
      Constraints,
      Type
    )
  ).
