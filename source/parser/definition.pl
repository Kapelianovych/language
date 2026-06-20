:- module(definition, [definition//2]).

:- use_module(library(dcgs)).
:- use_module(separator, [separators//0]).
:- use_module(identifier, [identifier//1]).

:- meta_predicate(definition(2, ?, ?, ?)).

definition(
  ExpressionFunctor,
  definition_node(
    AssignmentTarget,
    Value
  )
) -->
  identifier(AssignmentTarget),
  separators,
  "=",
  separators,
  phrase(ExpressionFunctor, Value).
