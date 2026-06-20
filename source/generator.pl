:- module(generator, [generate/2]).

/*  generator.pl  --  JavaScript code generation entry point.

    Given a program AST (as produced by `source/parser.pl`) this produces the
    equivalent JavaScript source as a list of characters.  The actual
    translation lives in `generator/javascript.pl`; here we just drive it with
    `phrase/2`.

    Pipeline position:  parse --> analyse (type check) --> generate.
*/

:- use_module(library(dcgs)).
:- use_module(generator/javascript, [program//1]).

%% generate(+AST, -JavaScript).
%
% `JavaScript` is the generated source as a character list.  `once/1` keeps
% generation deterministic (the grammar is unambiguous, but this guards
% against any spurious choice points).
generate(AST, JavaScript) :-
  once(phrase(program(AST), JavaScript)).
