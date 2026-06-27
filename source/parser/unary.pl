:- module(unary, [unary//2]).

:- use_module(library(dcgs)).
:- use_module(separator, [separators//0]).
:- use_module(position, [here//1, span_between/3]).

:- meta_predicate(unary(2, ?, ?, ?)).

unary(ExpressionFunctor, unary_node(Operator, Expression, Span)) -->
  here(Start),
  unary_operator(Operator),
  separators,
  phrase(ExpressionFunctor, Expression),
  here(End),
  { span_between(Start, End, Span) }.

unary_operator(number_negation) --> "-".
unary_operator(boolean_negation) --> "!".
unary_operator(bit_invertion) --> "~".
