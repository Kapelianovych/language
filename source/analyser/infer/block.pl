:- module(block, [infer_block/5]).

:- use_module(library(lists)).

:- use_module('../inference_state', [next_scope_state/2]).

:- meta_predicate(infer_block(4, ?, ?, ?, ?)).

infer_block(
  InferFunctor,
  Expressions,
  InferenceState,
  InferenceState,
  inferred(
    Assumptions,
    Constraints,
    Type
  )
) :-
  next_scope_state(InferenceState, ScopeInferenceState),
  infer_block_members(
    InferFunctor,
    Expressions,
    ScopeInferenceState,
    _,
    inferred(
      Assumptions,
      Constraints,
      Members
    )
  ),
  length(Members, Length),
  nth1(Length, Members, Type).

infer_block_members(
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
infer_block_members(
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
  infer_block_members(
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
