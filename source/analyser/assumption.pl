:- module(assumption, [extend_assumption/4,
                       remove_from_assumption/3,
                       lookup_in_assumption/3,
                       assumption_names/2]).

:- use_module(library(lists)).
:- use_module(library(pairs)).

%% lookup_in_assumption(+Name, +Assumptions, -Types).
lookup_in_assumption(_, [], []).
lookup_in_assumption(Name, [OtherName-_ | Assumptions], Types) :-
  Name \= OtherName,
  lookup_in_assumption(Name, Assumptions, Types).
lookup_in_assumption(Name, [Name-Type | Assumptions], [Type | Types]) :-
  lookup_in_assumption(Name, Assumptions, Types).

%% remove_from_assumptions(?Names, ?InitialAssumption, ?FinalAssumption).
remove_from_assumption([], Assumption, Assumption).
remove_from_assumption([Name | Names], InitialAssumption, FinalAssumption) :-
  once((
    (
      select(Name-_, InitialAssumption, IntermediateAssumption),
      remove_from_assumption([Name | Names], IntermediateAssumption, FinalAssumption)
    )
    ; remove_from_assumption(Names, InitialAssumption, FinalAssumption)
  )).

%% extend_assumption(+Name, +Type, +InitialList, -ExtendedList).
extend_assumption(Name, Type, InitialList, ExtendedList) :-
  append(InitialList, [Name-Type], ExtendedList).

%% assumption_names(+List, -Names).
assumption_names(Pairs, Names) :-
  pairs_keys(Pairs, Names).
