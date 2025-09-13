:- module(unary, [unary/4]).

:- use_module(library(dcgs)).

:- use_module(separator, [separators/2]).

:- meta_predicate(unary(2, ?, ?, ?)).

unary(ExpressionFunctor, unary_node(Operator, Expression)) -->
  unary_operator(Operator),
  separators,
  phrase(ExpressionFunctor, Expression).

unary_operator(number_negation) --> "-".
unary_operator(boolean_negation) --> "!".
unary_operator(bit_invertion) --> "~".
