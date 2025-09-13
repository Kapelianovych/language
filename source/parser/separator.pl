:- module(separator, [separator/2,
                      separators/2]).

:- use_module(library(dcgs)).

:- use_module(comment, [comment/3]).
:- use_module(whitespace, [whitespace/2,
                           whitespaces/2]).

separator -->
  whitespace
  | comment(_).

separators --> [].
separators -->
  separator,
  separators.
