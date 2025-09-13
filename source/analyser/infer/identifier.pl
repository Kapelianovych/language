:- module(identifier, [infer_identifier/4]).

:- use_module('../type', [fresh_type_variable/3]).
:- use_module('../assumption', [extend_assumption/4]).

infer_identifier(
  Name,
  InferenceState,
  NextInferenceState,
  inferred(
    Assumptions,
    [],
    Type
  )
) :-
  fresh_type_variable(InferenceState, NextInferenceState, Type),
  extend_assumption(Name, Type, [], Assumptions).
