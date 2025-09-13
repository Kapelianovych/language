:- module(whitespace, [new_line/2,
                       is_new_line/1,
                       whitespace/2,
                       whitespaces/2]).

:- use_module(library(dcgs)).

:- use_module(unicode, [unicode_character/2,
                        between_unicode_range/3]).

is_whitespace(Character) :-
  between_unicode_range(0x0009, 0x000D, Character)
  ; unicode_character(0x0020, Character)
  ; unicode_character(0x0085, Character)
  ; unicode_character(0x00A0, Character)
  ; unicode_character(0x1680, Character)
  ; between_unicode_range(0x2000, 0x200A, Character)
  ; unicode_character(0x2028, Character)
  ; unicode_character(0x2029, Character)
  ; unicode_character(0x202F, Character)
  ; unicode_character(0x205F, Character)
  ; unicode_character(0x3000, Character).

whitespace -->
  [Character],
  { is_whitespace(Character) }.

whitespaces --> [].
whitespaces -->
  whitespace,
  whitespaces.

is_new_line(Character) :-
  between_unicode_range(0x000A, 0x000D, Character)
  ; unicode_character(0x0085, Character)
  ; unicode_character(0x2028, Character)
  ; unicode_character(0x2029, Character).

new_line -->
  [Character],
  { is_new_line(Character) }.
