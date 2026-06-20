:- module(compiler, [
  compile/3,
  compile_file/1
]).

:- use_module(library(pio)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module(parser, [parse/2]).
:- use_module(analyser, [analyse/2]).
:- use_module(generator, [generate/2]).

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
% Compiles the `.sl` file at SourcePath, writing the generated JavaScript
% alongside it with a `.js` extension.  The source path must end in `.sl`;
% any other path raises domain_error(sl_source_file, SourcePath).
compile_file(SourcePath) :-
  once((
    % Derive the output path first so a wrong extension fails fast and loudly,
    % before we bother reading and compiling the file.
    ( phrase(output_path(OutputPath), SourcePath) ->
        true
    ; atom_chars(SourceAtom, SourcePath),
      domain_error(sl_source_file, SourceAtom)
    ),
    phrase_from_file(all_chars(Source), SourcePath),
    compile(Source, Output, _),
    phrase_to_file(Output, OutputPath)
  )).


% Match (or emit) an entire list of characters verbatim.
all_chars([]) --> [].
all_chars([C | Cs]) --> [C], all_chars(Cs).

output_path(OutputPath) -->
  all_chars(OutputPrefix),
  ".sl",
  { append(OutputPrefix, ".js", OutputPath) }.
