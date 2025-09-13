:- module(comment, [comment/3]).

:- use_module(library(dcgs)).
:- use_module(library(lists)).

:- use_module(whitespace, [new_line/2,
                           is_new_line/1,
                           whitespaces/2]).

comment(comment_node(Text)) -->
  comment_line(Text0),
  comment_tail(Text1),
  { append([Text0, "\n", Text1], Text) }.

comment_tail([]) --> [].
comment_tail(Text) -->
  whitespaces,
  comment_line(Line),
  comment_tail(Lines),
  { append([Line, "\n", Lines], Text) }.

comment_line(Text) -->
  "#",
  comment_line_text(Text),
  new_line.

comment_line_text([]) --> [].
comment_line_text([Character | Characters]) -->
  [Character],
  { \+ is_new_line(Character) },
  comment_line_text(Characters).
