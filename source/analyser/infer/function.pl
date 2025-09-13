:- module(function, [infer_function/6]).

:- use_module(library(lists)).
:- use_module(library(lambda)).

:- use_module('../type', [fresh_type_variable/3,
                          to_type_arrow/3]).
:- use_module('../assumption', [remove_from_assumption/3,
                                lookup_in_assumption/3]).
:- use_module('../inference_state', [next_scope_state/2,
                                     with_monomorphic_variables/3]).

:- meta_predicate(infer_function(4, ?, ?, ?, ?, ?)).

infer_function(
  InferFunctor,
  Parameters,
  Body,
  InferenceState,
  InferenceState,
  inferred(
    Assumptions,
    Constraints,
    Type
  )
) :-
  next_scope_state(InferenceState, ScopeInferenceState),
  infer_function_parameters(
    Parameters,
    ScopeInferenceState,
    IntermediateInferenceState,
    ParameterNames,
    ParameterTypes
  ),
  with_monomorphic_variables(
    ParameterNames,
    IntermediateInferenceState,
    IntermediateInferenceState1
  ),
  call(
    InferFunctor,
    Body,
    IntermediateInferenceState1,
    _,
    inferred(
      BodyAssumptions,
      BodyConstraints,
      ReturnType
    )
  ),
  remove_from_assumption(
    ParameterNames,
    BodyAssumptions,
    Assumptions
  ),
  generate_constraints_for_parameters(
    ParameterNames,
    ParameterTypes,
    BodyAssumptions,
    GeneratedConstraints
  ),
  append(BodyConstraints, GeneratedConstraints, Constraints),
  to_type_arrow(ParameterTypes, ReturnType, Type).

generate_constraints_for_parameters(
  [],
  [],
  _,
  []
).
generate_constraints_for_parameters(
  [ParameterName | ParameterNames],
  [GeneratedType | GeneratedTypes],
  BodyAssumptions,
  Constraints
) :-
  lookup_in_assumption(ParameterName, BodyAssumptions, AssumedTypes),
  maplist(
    GeneratedType+\AssumedType^subsumption_constraint(GeneratedType, AssumedType),
    AssumedTypes,
    Constraints1
  ),
  generate_constraints_for_parameters(
    ParameterNames,
    GeneratedTypes,
    BodyAssumptions,
    Constraints2
  ),
  append(Constraints1, Constraints2, Constraints).

infer_function_parameters(
  [],
  InferenceState,
  InferenceState,
  [],
  []
).
infer_function_parameters(
  [identifier_node(Name) | Parameters],
  InferenceState,
  NextInferenceState,
  [Name | Names],
  [Type | Types]
) :-
  fresh_type_variable(InferenceState, IntermediateInferenceState, Type),
  infer_function_parameters(
    Parameters,
    IntermediateInferenceState,
    NextInferenceState,
    Names,
    Types
  ).
