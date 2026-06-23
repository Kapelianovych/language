:- module(destructuring, [destructuring//2]).

/*  destructuring.pl  --  Destructuring definitions:

        (a b) = pair
        (first: x  second: y) = record

    The left-hand side is a RECORD pattern (so a bare `name = value` still
    parses as an ordinary definition, not destructuring).

    Produced AST:

        destructuring_node(RecordPattern, Value)
*/

:- use_module(library(dcgs)).
:- use_module(pattern, [irrefutable_record_pattern//2]).
:- use_module(separator, [separators//0]).

:- meta_predicate(destructuring(2, ?, ?, ?)).

destructuring(ExpressionFunctor, destructuring_node(Pattern, Value)) -->
  irrefutable_record_pattern(ExpressionFunctor, Pattern),
  separators,
  "=",
  separators,
  phrase(ExpressionFunctor, Value).
