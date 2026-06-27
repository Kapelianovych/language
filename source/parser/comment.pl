:- module(comment, [comment//1]).

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(whitespace, [
  new_line//0,
  is_new_line/1,
  whitespaces//0
]).
:- use_module(position, [here//1, span_between/3]).

comment(comment_node(Text, Span)) -->
  here(Start),
  comment_line(Text0),
  comment_tail(Text1),
  here(End),
  { append([Text0, "\n", Text1], Text),
    span_between(Start, End, Span)
  }.

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
