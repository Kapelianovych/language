:- module(parser, [parse/2]).

:- use_module(parser/program, [program/3]).

%% parse(+Input, -AST).
%
% Parses a program.
parse(Input, AST) :-
  once(phrase(program(AST), Input)).
