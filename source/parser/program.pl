:- module(program, [program/3]).

:- use_module(library(dcgs)).

:- use_module(separator, [separators/2]).
:- use_module(expression, [expression/3]).

program(program_node(Expressions)) -->
  separators,
  program_tail(Expressions).

program_tail([]) --> [].
program_tail([Expression | Expressions]) -->
  expression(Expression),
  separators,
  program_tail(Expressions).
