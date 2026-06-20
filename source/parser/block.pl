:- module(block, [block//2]).

:- use_module(library(dcgs)).
:- use_module(separator, [
  separator//0,
  separators//0
]).

:- meta_predicate(block(2, ?, ?, ?)).

block(ExpressionFunctor, block_node(Expressions)) -->
  "{",
  separators,
  block_section(ExpressionFunctor, Expressions),
  separators,
  "}".

block_section(_, []) --> [].
block_section(ExpressionFunctor, [Expression | Expressions]) -->
  phrase(ExpressionFunctor, Expression),
  block_section_tail(ExpressionFunctor, Expressions).

block_section_tail(_, []) --> [].
block_section_tail(ExpressionFunctor, [Expression | Expressions]) -->
  separator, % mandatory
  separators,
  phrase(ExpressionFunctor, Expression),
  block_section_tail(ExpressionFunctor, Expressions).
