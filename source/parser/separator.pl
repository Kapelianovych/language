:- module(separator, [separator/2,
                      separators/2]).

:- use_module(library(dcgs)).

:- use_module(comment, [comment/3]).
:- use_module(whitespace, [whitespace/2,
                           whitespaces/2]).

separator -->
  whitespace
  | comment(_).

% Greedy and deterministic.  Whitespace and comments are never part of a
% token, so consuming as many separators as possible is always the only
% correct choice -- there is never a reason to backtrack and keep fewer.
% The cut therefore commits as soon as a separator is seen, removing the
% choice point that the previous empty-first formulation left at every
% separator position.  Those choice points were the parser's main source
% of backtracking, so this is both behaviour-preserving and much faster.
separators -->
  separator,
  !,
  separators.
separators --> [].
