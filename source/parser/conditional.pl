:- module(conditional, [conditional//2]).

:- use_module(library(dcgs)).
:- use_module(separator, [separators//0]).
:- use_module(position, [here//1, span_between/3]).

:- meta_predicate(conditional(2, ?, ?, ?)).

conditional(
  ExpressionFunctor,
  conditional_node(Condition, Then, Else, Span)
) -->
  here(Start),
  "if",
  separators,
  phrase(ExpressionFunctor, Condition),
  separators,
  phrase(ExpressionFunctor, Then),
  separators,
  "else",
  separators,
  phrase(ExpressionFunctor, Else),
  here(End),
  { span_between(Start, End, Span) }.
