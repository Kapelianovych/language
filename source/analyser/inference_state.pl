:- module(inference_state, [next_scope_state/2,
                            next_variable_state/2,
                            get_state_counter/2,
                            with_monomorphic_variables/3]).

:- use_module(library(clpz)).
:- use_module(library(lists)).

%% next_scope_state(?PreviousInferenceState, ?NextInferenceState).
next_scope_state(
  inference_state(
    state_counter(ProgramId, ScopeId, _),
    MonomorphicVariables
  ),
  inference_state(
    state_counter(ProgramId, NextScopeId, 0),
    MonomorphicVariables
  )
) :-
  NextScopeId #= ScopeId + 1.

%% next_variable_state(?PreviousInferenceState, ?NextInferenceState).
next_variable_state(
  inference_state(
    state_counter(ProgramId, ScopeId, VariableId),
    MonomorphicVariables
  ),
  inference_state(
    state_counter(ProgramId, ScopeId, NextVariableId),
    MonomorphicVariables
  )
) :-
  NextVariableId #= VariableId + 1.

%% get_state_counter(+InferenceState, -StateCounter).
get_state_counter(
  inference_state(
    StateCounter,
    _
  ),
  StateCounter
).

%% with_monomorphic_variables(+Variables, +InferenceState, -NextInferenceState).
with_monomorphic_variables(
  Variables,
  inference_state(
    StateCounter,
    monomorphic_variables(Set)
  ),
  inference_state(
    StateCounter,
    monomorphic_variables(NextSet)
  )
) :-
  append(Set, Variables, AppendedSet),
  list_to_set(AppendedSet, NextSet).
