:- module(function, [function//2]).

:- use_module(library(dcgs)).
:- use_module(identifier, [identifier//1]).
:- use_module(separator, [
  separator//0,
  separators//0
]).

:- meta_predicate(function(2, ?, ?, ?)).

function(ExpressionFunctor, function_node(Parameters, Body)) -->
  "(",
  separators,
  function_parameters(Parameters),
  separators,
  ")",
  separators,
  phrase(ExpressionFunctor, Body).

function_parameters([]) --> [].
function_parameters([Parameter | Parameters]) -->
  identifier(Parameter),
  function_parameters_tail(Parameters).

function_parameters_tail([]) --> [].
function_parameters_tail([Parameter | Parameters]) -->
  separator, % mandatory
  separators,
  identifier(Parameter),
  function_parameters_tail(Parameters).
