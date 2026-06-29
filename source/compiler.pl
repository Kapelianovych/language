:- module(compiler, [
  compile/3,
  compile_file/1
]).

:- use_module(library(pio)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module('syntax/lower', [parse_source/2]).
:- use_module(analyser, [analyse/2]).
:- use_module(generator, [generate/2]).
:- use_module(module_loader, [compile_program/1]).
:- use_module('transformation/macro', [check_macros/1, expand_macros/2]).

%% compile(+Source, -Output, -AnalysisResult).
%
% Compiles source text into output text.
compile(Source, Output, AnalysisResult) :-
  once((
    parse_source(Source, ParsedAst),
    % Process reader macros (type-check bodies, then expand invocations) before
    % type-checking and generating the resulting program.
    check_macros(ParsedAst),
    expand_macros(ParsedAst, Ast),
    analyse(Ast, AnalysisResult),
    generate(Ast, Output)
  )).

%% compile_file(+SourcePath).
%
% Compiles the `.sl` file at SourcePath together with every module it imports
% (directly or transitively), writing each module's JavaScript alongside it
% with a `.js` extension.  The entry path must end in `.sl`; any other path
% raises domain_error(sl_source_file, SourcePath).
compile_file(SourcePath) :-
  % Check the extension first so a wrong one fails fast and loudly.
  ( phrase(output_path(_OutputPath), SourcePath) ->
      true
  ; atom_chars(SourceAtom, SourcePath),
    domain_error(sl_source_file, SourceAtom)
  ),
  compile_program(SourcePath).

% Match (or emit) an entire list of characters verbatim.
all_chars([]) --> [].
all_chars([C | Cs]) --> [C], all_chars(Cs).

output_path(OutputPath) -->
  all_chars(OutputPrefix),
  ".sl",
  { append(OutputPrefix, ".js", OutputPath) }.
