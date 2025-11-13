:- module(binary, [binary/4, failing_binary/4]).

:- use_module(library(dcgs)).
:- use_module(library(clpz)).
:- use_module(library(reif)).

:- use_module(separator, [separators/2]).

:- meta_predicate(binary(2, ?, ?, ?)).

%% failing_binary(?, ?).
% Binary predicate that always fails. It replaces the binary
% predicate in the expression, so there won't be infinite recursion
% in the binary operand position.
failing_binary(_, _) --> { false }.

binary(
  BaseExpressionFunctor,
  Node
) -->
  phrase(BaseExpressionFunctor, failing_binary, LeftExpression),
  separators,
  binary_operator(Operator, Precedence),
  separators,
  phrase(BaseExpressionFunctor, failing_binary, RightExpression),
  binary_tail(
    BaseExpressionFunctor,
    Precedence,
    binary_node(Operator, LeftExpression, RightExpression),
    Node
  ).

binary_tail(_, _, Node, Node) --> [].
binary_tail(
  BaseExpressionFunctor,
  LeftBinaryNodeOperatorPrecedence,
  binary_node(
    LeftOperator,
    LeftBinaryNodeLeftExpression,
    LeftBinaryNodeRightExpression
  ),
  Node
) -->
  separators,
  binary_operator(CurrentOperator, CurrentOperatorPrecedence),
  separators,
  phrase(BaseExpressionFunctor, failing_binary, CurrentRightExpression),
  {
    if_(
      has_right_operator_less_importance(
        LeftBinaryNodeOperatorPrecedence,
        CurrentOperatorPrecedence
      ),
      (
        Operator = CurrentOperator,
        Precedence = CurrentOperatorPrecedence,
        LeftExpression = binary_node(
          LeftOperator,
          LeftBinaryNodeLeftExpression,
          LeftBinaryNodeRightExpression
        ),
        RightExpression = CurrentRightExpression
      ),
      (
        Operator = LeftOperator,
        Precedence = LeftBinaryNodeOperatorPrecedence,
        LeftExpression = LeftBinaryNodeLeftExpression,
        RightExpression = binary_node(
          CurrentOperator,
          LeftBinaryNodeRightExpression,
          CurrentRightExpression
        )
      )
    )
  },
  binary_tail(
    BaseExpressionFunctor,
    Precedence,
    binary_node(
      Operator,
      LeftExpression,
      RightExpression
    ),
    Node
  ).

has_right_operator_less_importance(
  LeftOperatorPrecedence,
  RightOperatorPrecedence,
  true
) :-
  LeftOperatorPrecedence #>= RightOperatorPrecedence.
has_right_operator_less_importance(
  LeftOperatorPrecedence,
  RightOperatorPrecedence,
  false
) :-
  LeftOperatorPrecedence #< RightOperatorPrecedence.

binary_operator(multiplication, 9) --> "*".
binary_operator(division, 9) --> "/".
binary_operator(addition, 8) --> "+".
binary_operator(subtraction, 8) --> "-".
binary_operator(left_bit_shift, 7) --> "<<".
binary_operator(right_bit_shift, 7) --> ">>".
binary_operator(less_than_or_equal, 6) --> "<=".
binary_operator(less_than, 6) --> "<".
binary_operator(greater_than_or_equal, 6) --> ">=".
binary_operator(greater_than, 6) --> ">".
binary_operator(equal, 5) --> "==".
binary_operator(not_equal, 5) --> "!=".
binary_operator(and, 4) --> "&".
binary_operator(xor, 3) --> "^".
binary_operator(or, 2) --> "|".
binary_operator(pipe, 1) --> "->".
