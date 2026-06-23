:- module(compiler, [
  compile/3,
  compile_file/1,
  compile_program/1
]).

:- use_module(library(pio)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module(parser, [parse/2]).
:- use_module(analyser, [analyse/2]).
:- use_module(generator, [generate/2]).
:- use_module(module_loader, [compile_program/1]).

%% compile(+Source, -Output, -AnalysisResult).
%
% Compiles source text into output text.
compile(Source, Output, AnalysisResult) :-
  once((
    parse(Source, Ast),
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
