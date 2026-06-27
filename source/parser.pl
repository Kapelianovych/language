:- module(parser, [parse/2]).

:- use_module(parser/program, [program//1]).
:- use_module(parser/position, [set_input_length/1]).

%% parse(+Input, -AST).
%
% Parses a program.  `Input` is a list of character atoms; the produced AST
% carries a `span(Start, End)` of 0-based character offsets on every node (see
% `parser/position.pl`).  The input length is recorded first so span capture
% can convert captured input suffixes into absolute offsets.
parse(Input, AST) :-
  set_input_length(Input),
  once(phrase(program(AST), Input)).
