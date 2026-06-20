:- module(string_literal, [string_literal//2]).

:- use_module(library(dif)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).

:- use_module(separator, [separators//0]).

:- meta_predicate(string_literal(2, ?, ?, ?)).

string_literal(ExpressionFunctor, string_node(Parts)) -->
  "'",
  string(ExpressionFunctor, MixedParts),
  { foldl(normalise_parts, MixedParts, [string_static_part("")], Parts) },
  "'".

normalise_parts(
  string_interpolated_part(Node),
  PreviousParts,
  NextParts
) :-
  append(PreviousParts, [string_interpolated_part(Node)], NextParts).
normalise_parts(
  Character,
  PreviousParts,
  NextParts
) :-
  length(PreviousParts, PreviousPartsLength),
  nth1(
    PreviousPartsLength,
    PreviousParts,
    string_static_part(Text),
    InitParts
  ),
  append(Text, [Character], NewText),
  append(InitParts, [string_static_part(NewText)], NextParts).
normalise_parts(
  Character,
  PreviousParts,
  NextParts
) :-
  length(PreviousParts, PreviousPartsLength),
  nth1(PreviousPartsLength, PreviousParts, string_interpolated_part(_)),
  append(PreviousParts, [string_static_part([Character])], NextParts).

string(_, []) --> [].
string(ExpressionFunctor, [Part | Parts]) -->
  (
    escaped_special_character(Part)
    | escaped_any_character(Part)
    | interpolated_expression(ExpressionFunctor, Part)
    | static_character(Part)
  ),
  string(ExpressionFunctor, Parts).

escaped_special_character(Character) -->
  "\\",
  [Character],
  { member(Character, "{'")}.

escaped_any_character('\\') --> "\\".

interpolated_expression(
  ExpressionFunctor,
  string_interpolated_part(Part)
) -->
  "{",
  separators,
  phrase(ExpressionFunctor, Part),
  separators,
  "}".

static_character(Character) -->
  [Character],
  { maplist(dif(Character), "'\\{") }.
