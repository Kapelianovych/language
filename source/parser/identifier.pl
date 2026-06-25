:- module(identifier, [identifier//1]).

:- use_module(library(dcgs)).
:- use_module('../unicode', [xid_start/1, xid_continue/1]).

% An identifier is an XID_Start character followed by zero or more
% XID_Continue characters (Unicode UAX #31).  The XID property tables live in
% the generated `source/unicode.pl`; this rule is just the DCG over them.
identifier(identifier_node([FirstCharacter | RestCharacters])) -->
  identifier_first_character(FirstCharacter),
  identifier_rest_characters(RestCharacters).

identifier_first_character(Character) -->
  [Character],
  { char_code(Character, Code), xid_start(Code) }.

identifier_rest_characters([ContinueCharacter | Characters]) -->
  identifier_continue_character(ContinueCharacter),
  identifier_rest_characters(Characters).
% The default clause has to be the last definition to enforce Prolog
% to report the largest available token as identifier first.
identifier_rest_characters([]) --> [].

identifier_continue_character(Character) -->
  [Character],
  { char_code(Character, Code), xid_continue(Code) }.
