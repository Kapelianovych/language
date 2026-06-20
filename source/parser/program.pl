:- module(program, [program//1]).

:- use_module(library(dcgs)).
:- use_module(separator, [separators//0]).
:- use_module(expression, [expression//1]).

program(program_node(Expressions)) -->
  separators,
  program_tail(Expressions).

program_tail([]) --> [].
program_tail([Expression | Expressions]) -->
  expression(Expression),
  separators,
  program_tail(Expressions).
