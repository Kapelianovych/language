:- module(string, [infer_string/5]).

:- use_module(library(lists)).

:- use_module('../type', [fresh_type_variable/3]).

:- meta_predicate(infer_string(4, ?, ?, ?, ?)).

infer_string(
  InferFunctor,
  Parts,
  InferenceState,
  NextInferenceState,
  inferred(
    Assumptions,
    Constraints,
    Type
  )
) :-
  fresh_type_variable(InferenceState, VariableInferenceState, Type),
  infer_string_parts(
    InferFunctor,
    Parts,
    VariableInferenceState,
    NextInferenceState,
    inferred(
      Assumptions,
      ExpressionConstraints,
      ExpressionTypes
    )
  ),
  append(
    ExpressionConstraints,
    [subsumption_constraint(Type, type_constant(string(ExpressionTypes)))],
    Constraints
  ).

infer_string_parts(
  _,
  [],
  InferenceState,
  InferenceState,
  inferred([], [], [])
).
infer_string_parts(
  InferFunctor,
  [string_static_part(Text) | Expressions],
  InferenceState,
  NextInferenceState,
  inferred(
    Assumptions,
    Constraints,
    [type_constant(string(Text)) | Types]  
  )
) :-
  infer_string_parts(
    InferFunctor,
    Expressions,
    InferenceState,
    NextInferenceState,
    inferred(
      Assumptions,
      Constraints,
      Types
    )
  ).
infer_string_parts(
  InferFunctor,
  [string_interpolated_part(Expression) | Expressions],
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
      ExpressionAssumptions,
      ExpressionConstraints,
      Type
    )
  ),
  infer_string_parts(
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
  append(
    [
      ExpressionConstraints,
      [subsumption_constraint(Type, type_constant(string))],
      RestConstraints
    ],
    Constraints
  ),
  append(ExpressionAssumptions, RestAssumptions, Assumptions).
