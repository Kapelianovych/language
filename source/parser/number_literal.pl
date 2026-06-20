:- module(number_literal, [number_literal//1]).

:- use_module(library(dcgs)).

number_literal(number_node(Number)) -->
  binary_number_literal(Number)
  | octal_number_literal(Number)
  | decimal_number_literal(Number)
  | hexadecimal_number_literal(Number).

%% integer_literal(+DigitFunctor, +Radix, -Number, -DigitsCount).
%
% Parses any integer literal and converts it into a decimal number.
integer_literal(
  DigitFunctor,
  Radix,
  Number,
  DigitsCount
) -->
  phrase(DigitFunctor, FirstDigit),
  integer_literal_tail(DigitFunctor, Radix, RestDigits, RestDigitsCount),
  {
    % RestDigitsCount and RestDigits are ground once the tail is parsed, so
    % plain `is` suffices -- no need for clpz constraints.
    DigitsCount is RestDigitsCount + 1,
    Number is FirstDigit * Radix ^ RestDigitsCount + RestDigits
  }.

integer_literal_tail(
  DigitFunctor,
  Radix,
  Number,
  DigitsCount
) -->
  ("," | ""),
  phrase(DigitFunctor, Digit),
  integer_literal_tail(DigitFunctor, Radix, RestDigits, RestDigitsCount),
  {
    DigitsCount is RestDigitsCount + 1,
    Number is Digit * Radix ^ RestDigitsCount + RestDigits
  }.
% Force Prolog to suggest full number as the first proposed answer.
% It must be the last clause of the phrase predicate to have greediness.
integer_literal_tail(_, _, 0, 0) --> [].

binary_number_literal(Number) -->
  "0",
  ("b" | "B"),
  integer_literal(binary_digit, 2, Number, _).

binary_digit(0) --> "0".
binary_digit(1) --> "1".

octal_number_literal(Number) -->
  "0",
  ("o" | "O"),
  integer_literal(octal_digit, 8, Number, _).

octal_digit(2) --> "2".
octal_digit(3) --> "3".
octal_digit(4) --> "4".
octal_digit(5) --> "5".
octal_digit(6) --> "6".
octal_digit(7) --> "7".
octal_digit(Digit) -->
  binary_digit(Digit).

decimal_number_literal(Number) -->
  scientific_number_literal(Number)
  | floating_point_number_literal(Number)
  | integer_number_literal(Number).

integer_number_literal(Number) -->
  integer_literal(decimal_digit, 10, Number, _).

decimal_digit(8) --> "8".
decimal_digit(9) --> "9".
decimal_digit(Digit) -->
  octal_digit(Digit).

floating_point_number_literal(Number) -->
  integer_number_literal(IntegerPart),
  ".",
  integer_literal(decimal_digit, 10, FloatingPart, FloatingPartDigitsCount),
  { Number is IntegerPart + FloatingPart / 10 ^ FloatingPartDigitsCount }.

scientific_number_literal(Number) -->
  (
    floating_point_number_literal(Significand)
    | integer_number_literal(Significand)
  ),
  ("e" | "E"),
  optional_sign(Sign),
  integer_number_literal(ExponentPart),
  { Number is Significand * 10.0 ^ (Sign * ExponentPart) }.

optional_sign(-1) --> "-".
optional_sign(1) --> "+" | "".

hexadecimal_number_literal(Number) -->
  "0",
  ("x" | "X"),
  integer_literal(hexadecimal_digit, 16, Number, _).

hexadecimal_digit(10) --> "a" | "A".
hexadecimal_digit(11) --> "b" | "B".
hexadecimal_digit(12) --> "c" | "C".
hexadecimal_digit(13) --> "d" | "D".
hexadecimal_digit(14) --> "e" | "E".
hexadecimal_digit(15) --> "f" | "F".
hexadecimal_digit(Digit) -->
  decimal_digit(Digit).
