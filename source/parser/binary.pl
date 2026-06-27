:- module(binary, [
  binary//2,
  failing_binary//2
]).

:- use_module(library(dcgs)).
:- use_module(separator, [separators//0]).
:- use_module(position, [span_cover/3]).

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
  % A binary node's span covers its left and right operands (each already
  % carries its own span); this holds for the re-associated nodes below too.
  { span_cover(LeftExpression, RightExpression, Span) },
  binary_tail(
    BaseExpressionFunctor,
    Precedence,
    binary_node(Operator, LeftExpression, RightExpression, Span),
    Node
  ).

binary_tail(_, _, Node, Node) --> [].
binary_tail(
  BaseExpressionFunctor,
  LeftBinaryNodeOperatorPrecedence,
  binary_node(
    LeftOperator,
    LeftBinaryNodeLeftExpression,
    LeftBinaryNodeRightExpression,
    _LeftSpan
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
    % the constraint-solver overhead on every operator.  Each re-associated
    % `binary_node` recomputes its span from its (re-grouped) operands.
    ( LeftBinaryNodeOperatorPrecedence >= CurrentOperatorPrecedence ->
        Operator = CurrentOperator,
        Precedence = CurrentOperatorPrecedence,
        span_cover(LeftBinaryNodeLeftExpression, LeftBinaryNodeRightExpression, LeftExpressionSpan),
        LeftExpression = binary_node(
          LeftOperator,
          LeftBinaryNodeLeftExpression,
          LeftBinaryNodeRightExpression,
          LeftExpressionSpan
        ),
        RightExpression = CurrentRightExpression
    ;   Operator = LeftOperator,
        Precedence = LeftBinaryNodeOperatorPrecedence,
        LeftExpression = LeftBinaryNodeLeftExpression,
        span_cover(LeftBinaryNodeRightExpression, CurrentRightExpression, RightExpressionSpan),
        RightExpression = binary_node(
          CurrentOperator,
          LeftBinaryNodeRightExpression,
          CurrentRightExpression,
          RightExpressionSpan
        )
    ),
    span_cover(LeftExpression, RightExpression, Span)
  },
  binary_tail(
    BaseExpressionFunctor,
    Precedence,
    binary_node(
      Operator,
      LeftExpression,
      RightExpression,
      Span
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
