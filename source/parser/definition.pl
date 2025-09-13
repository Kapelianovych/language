:- module(definition, [definition/4]).

:- use_module(library(dcgs)).

:- use_module(separator, [separators/2]).
:- use_module(identifier, [identifier/3]).

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
