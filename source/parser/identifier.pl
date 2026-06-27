:- module(identifier, [identifier//1, qualified_identifier//2]).

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module('../unicode', [xid_start/1, xid_continue/1]).
:- use_module(position, [here//1, span_between/3]).

% An identifier is an XID_Start character followed by zero or more
% XID_Continue characters (Unicode UAX #31).  The XID property tables live in
% the generated `source/unicode.pl`; this rule is just the DCG over them.
% Every identifier name is canonicalised to a plain character-atom list (via an
% atom round-trip).  Names are used as `assoc` keys throughout the compiler, and
% `library(assoc)` orders keys with `compare/3`, whose result is sensitive to a
% list's internal representation (a `phrase_from_file` partial string vs a cons
% list built by `append`).  Forcing ONE representation at the single point every
% name originates keeps qualified names built later (by the module expander and
% loader) comparable to names the parser produced -- otherwise equal-looking
% keys sort inconsistently and the AVL tree silently loses entries.
identifier(identifier_node(Name, Span)) -->
  here(Start),
  identifier_first_character(FirstCharacter),
  identifier_rest_characters(RestCharacters),
  here(End),
  { plain_chars([FirstCharacter | RestCharacters], Name),
    span_between(Start, End, Span)
  }.

% Rebuild a list as fresh cons cells of character atoms.  `phrase_from_file`
% backs its list with a partial string, and `compare/3` (which `library(assoc)`
% orders keys by) treats a partial string and an equal cons list as DIFFERENT,
% so names of mixed provenance used as keys would sort inconsistently and the
% AVL tree would silently lose entries.  An `atom_chars` round trip does NOT
% help (it preserves the partial-string backing); only a true cons rebuild
% gives one comparable representation.  Names originate here, so doing it once
% in `identifier//1` keeps every name -- and the qualified names later built
% from them by appending -- consistently comparable.
plain_chars([], []).
plain_chars([Character | Characters], [Character | Rest]) :-
  plain_chars(Characters, Rest).

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

% A possibly-DOTTED identifier: one or more identifiers joined by `.`, returned
% as a single flat character list with the dots kept (`Math.Option` ->
% "Math.Option").  Used where a qualified name from a module namespace appears
% in a position that has no other meaning for `.` -- a TYPE reference and a
% CONSTRUCTOR pattern.  (In value/expression position `.` is member access, so
% qualified value names are formed there from access nodes instead.)  Since a
% source identifier contains no `.`, the joined form is unambiguous and cannot
% collide with a plain identifier.
% Also returns the `Span` covering the whole dotted name (`Math.Option`), so a
% qualified reference is locatable even though its joined `Name` is a single
% flat character list.
qualified_identifier(Name, Span) -->
  here(Start),
  identifier(identifier_node(First, _)),
  qualified_identifier_tail(Rest),
  here(End),
  { append(First, Rest, Joined),
    plain_chars(Joined, Name),            % keep one comparable representation (see plain_chars/2)
    span_between(Start, End, Span)
  }.

qualified_identifier_tail(Name) -->
  ".",
  identifier(identifier_node(Segment, _)),
  qualified_identifier_tail(Rest),
  { append(['.' | Segment], Rest, Name) }.
qualified_identifier_tail([]) --> [].
