:- module(operators, [
  unary_signature/4,
  binary_signature/7
]).

/*  operators.pl  --  Built-in types of the primitive operators.

    The source language has no way to *write* a type, so the only
    polymorphism a program can observe comes from let-generalisation and
    from the handful of operators that are intrinsically polymorphic
    (structural equality and the pipe).  Each operator is given a type
    here; the inference engine simply unifies the operand types against
    these signatures.

    Design decisions (the grammar fixes the operators but not their
    semantics, so these are the principled choices made by this checker):

      * `- ! ~`            unary negation / logical not / bitwise not
      * `* / + -`          arithmetic on numbers
      * `<< >>`            bit shifts on numbers
      * `& ^ |`            boolean logical and / xor / or, on booleans
      * `< <= > >=`        numeric comparison, yielding boolean
      * `== !=`            structural equality, polymorphic: (a a) -> boolean
      * `->`               pipe: `x -> f` feeds `x` to a unary function `f`,
                           so it has type `a (a -> b) -> b`
*/

:- use_module(types, [fresh_unification_variable/4]).

%% unary_signature(+Operator, +Level, -OperandType, -ResultType).
%
% (Level is accepted for symmetry with binary_signature; the unary
% operators are monomorphic so it is unused.)
unary_signature(number_negation,  _Level, number,  number).
unary_signature(boolean_negation, _Level, boolean, boolean).
unary_signature(bit_invertion,    _Level, number,  number).

%% binary_signature(+Operator, +Level, +CtxIn, -LeftType, -RightType, -ResultType, -CtxOut).
%
% Yields the expected operand types and the result type of a binary
% operator.  Polymorphic operators allocate fresh unification variables
% (at the current `Level`), hence the threaded context.
binary_signature(Operator, Level, CtxIn, Left, Right, Result, CtxOut) :-
  ( numeric_binary(Operator) ->
      Left = number, Right = number, Result = number, CtxOut = CtxIn
  ; logical_binary(Operator) ->
      Left = boolean, Right = boolean, Result = boolean, CtxOut = CtxIn
  ; comparison_binary(Operator) ->
      Left = number, Right = number, Result = boolean, CtxOut = CtxIn
  ; equality_binary(Operator) ->
      % (a a) -> boolean : both operands share one fresh variable.
      fresh_unification_variable(CtxIn, Level, A, CtxOut),
      Left = A, Right = A, Result = boolean
  ; Operator = pipe ->
      % a (a -> b) -> b : the right operand must be a unary function whose
      % parameter type matches the left operand.
      fresh_unification_variable(CtxIn, Level, A, Ctx1),
      fresh_unification_variable(Ctx1, Level, B, CtxOut),
      Left = A,
      Right = function_type([A], B),
      Result = B
  ).

% Operators whose signature is (number number) -> number.
numeric_binary(multiplication).
numeric_binary(division).
numeric_binary(addition).
numeric_binary(subtraction).
numeric_binary(left_bit_shift).
numeric_binary(right_bit_shift).

% Operators whose signature is (boolean boolean) -> boolean.
logical_binary(and).
logical_binary(xor).
logical_binary(or).

% Operators whose signature is (number number) -> boolean.
comparison_binary(less_than).
comparison_binary(less_than_or_equal).
comparison_binary(greater_than).
comparison_binary(greater_than_or_equal).

% Operators whose signature is (a a) -> boolean.
equality_binary(equal).
equality_binary(not_equal).
