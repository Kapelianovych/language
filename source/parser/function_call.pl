:- module(function_call, [function_call//2]).

:- use_module(library(dcgs)).
:- use_module(block, [block//2]).
:- use_module(identifier, [identifier//1]).
:- use_module(separator, [
  separator//0,
  separators//0
]).

:- meta_predicate(function_call(2, ?, ?, ?)).

function_call(ExpressionFunctor, function_call_node(Target, Arguments)) -->
  (
    block(ExpressionFunctor, Target)
    | identifier(Target)
  ),
  separators,
  "(",
  separators,
  function_arguments(ExpressionFunctor, Arguments),
  separators,
  ")".

function_arguments(_, []) --> [].
function_arguments(ExpressionFunctor, [Argument | Arguments]) -->
  phrase(ExpressionFunctor, Argument),
  function_arguments_tail(ExpressionFunctor, Arguments).

function_arguments_tail(_, []) --> [].
function_arguments_tail(ExpressionFunctor, [Argument | Arguments]) -->
  separator, % mandatory
  separators,
  phrase(ExpressionFunctor, Argument),
  function_arguments_tail(ExpressionFunctor, Arguments).
