:- module(function_call, [function_call/4]).

:- use_module(library(dcgs)).

:- use_module(block, [block/4]).
:- use_module(identifier, [identifier/3]).
:- use_module(separator, [separator/2,
                           separators/2]).

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
