:- module(tuple, [tuple//2]).

:- use_module(library(dcgs)).
:- use_module(separator, [
  separator//0,
  separators//0
]).

:- meta_predicate(tuple(2, ?, ?, ?)).

tuple(ExpressionFunctor, tuple_node(Expressions)) -->
  "(",
  separators,
  tuple_section(ExpressionFunctor, Expressions),
  separators,
  ")".

tuple_section(_, []) --> [].
tuple_section(ExpressionFunctor, [Expression | Expressions]) -->
  phrase(ExpressionFunctor, Expression),
  tuple_section_tail(ExpressionFunctor, Expressions).

tuple_section_tail(_, []) --> [].
tuple_section_tail(ExpressionFunctor, [Expression | Expressions]) -->
  separator, % mandatory
  separators,
  phrase(ExpressionFunctor, Expression),
  tuple_section_tail(ExpressionFunctor, Expressions).
