:- module(boolean_literal, [boolean_literal//1]).

:- use_module(library(dcgs)).
:- use_module(position, [here//1, span_between/3]).

boolean_literal(boolean_node(true, Span)) -->
  here(Start), "true", here(End), { span_between(Start, End, Span) }.
boolean_literal(boolean_node(false, Span)) -->
  here(Start), "false", here(End), { span_between(Start, End, Span) }.
