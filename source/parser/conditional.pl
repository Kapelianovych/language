:- module(conditional, [conditional/4]).

:- use_module(library(dcgs)).

:- use_module(separator, [separators/2]).

:- meta_predicate(conditional(2, ?, ?, ?)).

conditional(
  ExpressionFunctor,
  conditional_node(Condition, Then, Else)
) -->
  "if",
  separators,
  phrase(ExpressionFunctor, Condition),
  separators,
  phrase(ExpressionFunctor, Then),
  separators,
  "else",
  separators,
  phrase(ExpressionFunctor, Else).
