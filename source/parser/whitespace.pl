:- module(whitespace, [
  new_line//0,
  is_new_line/1,
  is_whitespace/1,
  whitespace//0,
  whitespaces//0
]).

:- use_module(library(dcgs)).

% Convert the character to its codepoint once, then test the codepoint
% against the whitespace ranges.  (The previous version re-ran char_code/2
% inside every disjunct.)
is_whitespace(Character) :-
  char_code(Character, Code),
  whitespace_code(Code).

whitespace_code(Code) :- Code >= 0x0009, Code =< 0x000D.
whitespace_code(0x0020).
whitespace_code(0x0085).
whitespace_code(0x00A0).
whitespace_code(0x1680).
whitespace_code(Code) :- Code >= 0x2000, Code =< 0x200A.
whitespace_code(0x2028).
whitespace_code(0x2029).
whitespace_code(0x202F).
whitespace_code(0x205F).
whitespace_code(0x3000).

whitespace -->
  [Character],
  { is_whitespace(Character) }.

% Greedy and deterministic, for the same reason as `separators`: a run of
% whitespace has only one sensible reading, so commit to consuming it all.
whitespaces -->
  whitespace,
  !,
  whitespaces.
whitespaces --> [].

is_new_line(Character) :-
  char_code(Character, Code),
  new_line_code(Code).

new_line_code(Code) :- Code >= 0x000A, Code =< 0x000D.
new_line_code(0x0085).
new_line_code(0x2028).
new_line_code(0x2029).

new_line -->
  [Character],
  { is_new_line(Character) }.
