:- module(binary, [
  binary//2,
  failing_binary//2
]).

:- use_module(library(dcgs)).
:- use_module(separator, [separators//0]).

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
    % Operator precedences are always ground integers here, so a plain
    % arithmetic comparison and if-then-else behaves exactly like the former
    % clpz/reif `if_(has_right_operator_less_importance(...), ...)` -- without
    % the constraint-solver overhead on every operator.
    ( LeftBinaryNodeOperatorPrecedence >= CurrentOperatorPrecedence ->
        Operator = CurrentOperator,
        Precedence = CurrentOperatorPrecedence,
        LeftExpression = binary_node(
          LeftOperator,
          LeftBinaryNodeLeftExpression,
          LeftBinaryNodeRightExpression
        ),
        RightExpression = CurrentRightExpression
    ;   Operator = LeftOperator,
        Precedence = LeftBinaryNodeOperatorPrecedence,
        LeftExpression = LeftBinaryNodeLeftExpression,
        RightExpression = binary_node(
          CurrentOperator,
          LeftBinaryNodeRightExpression,
          CurrentRightExpression
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

% NOTE on clause order: longer spellings must come first so a doubled
% operator is not mis-read as two single ones.  `&&`/`^^`/`||` (bitwise, on
% numbers) therefore precede `&`/`^`/`|` (boolean, on booleans), exactly as
% `<<`/`<=` precede `<`.  The doubled forms bind TIGHTER than comparison so
% `a && b == 0` groups as `(a && b) == 0`; the single boolean forms stay the
% loosest (just above pipe), matching their original precedences.
binary_operator(multiplication, 12) --> "*".
binary_operator(division, 12) --> "/".
binary_operator(addition, 11) --> "+".
binary_operator(subtraction, 11) --> "-".
binary_operator(left_bit_shift, 10) --> "<<".
binary_operator(right_bit_shift, 10) --> ">>".
binary_operator(bitwise_and, 9) --> "&&".
binary_operator(bitwise_xor, 8) --> "^^".
binary_operator(bitwise_or, 7) --> "||".
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
