:- module(type, [fresh_type_variable/3,
                 to_type_arrow/3]).

:- use_module(library(lists)).
:- use_module(library(format)).

:- use_module(inference_state, [get_state_counter/2,
                                next_variable_state/2]).

%% fresh_type_variable(?CurrentInferenceState, ?NextInferenceState, ?Type).
fresh_type_variable(
  InferenceState,
  NextInferenceState,
  type_variable(Id)
) :-
  next_variable_state(InferenceState, NextInferenceState),
  get_state_counter(
    NextInferenceState,
    state_counter(ProgramId, ScopeId, VariableId)
  ),
  phrase(format_("~d~d~d", [ProgramId, ScopeId, VariableId]), NumericId),
  append("T", NumericId, Id).

%% to_type_arrow(+Inputs, +Output, -Type).
to_type_arrow([], Output, Output).
to_type_arrow([Input | Inputs], Output, type_arrow(Input, Type)) :-
  to_type_arrow(Inputs, Output, Type).
