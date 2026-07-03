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
:- use_module(module_loader, [compile_program/3]).
:- use_module(module_paths, [source_to_js_path/2]).
:- use_module('transformation/macro', [check_macros/1, expand_macros/2]).
:- use_module('transformation/module', [expand_modules/2]).

%% compile(+Source, -Output, -AnalysisResult).
%
% Compiles source text into output text.
compile(Source, Output, AnalysisResult) :-
  once((
    parse_source(Source, ParsedAst),
    % Process reader macros (type-check bodies, then expand invocations) before
    % type-checking and generating the resulting program.
    check_macros(ParsedAst),
    expand_macros(ParsedAst, ExpandedAst),
    expand_modules(ExpandedAst, Ast),
    analyse(Ast, AnalysisResult),
    generate(Ast, Output)
  )).

%% compile_file(+SourcePath).
%
% Compiles the `.sl` file at SourcePath together with every module it imports
% (directly or transitively), writing each module's JavaScript alongside it
% with a `.js` extension.  The entry path must end in `.sl`; any other path
% raises domain_error(sl_source_file, SourcePath).
%
% This is the IMPERATIVE SHELL around the pure loader: `compile_program/3`
% reads sources only through the resolver we pass it (here the filesystem,
% `module_paths:read_source_chars/2` -- module-qualified because the closure
% is invoked inside `module_loader`, which does not import it) and returns
% the generated JavaScript instead of writing it.  All filesystem output
% happens below, and only after the WHOLE graph compiled cleanly -- a failed
% compile therefore never leaves partially updated `.js` files behind.
% Callers that hold sources elsewhere (an editor buffer, a test fixture) call
% `compile_program/3` directly with their own resolver, and are free to
% ignore the returned artifacts entirely (check-only).
compile_file(SourcePath) :-
  % Check the extension first so a wrong one fails fast and loudly.
  ( phrase(output_path(_OutputPath), SourcePath) ->
      true
  ; atom_chars(SourceAtom, SourcePath),
    domain_error(sl_source_file, SourceAtom)
  ),
  compile_program(SourcePath, module_paths:read_source_chars, CompiledModules),
  write_compiled_modules(CompiledModules).

% Each module's JavaScript lands beside its source, extension swapped.
write_compiled_modules([]).
write_compiled_modules([Module - JavaScript | Rest]) :-
  source_to_js_path(Module, JsPath),
  phrase_to_file(JavaScript, JsPath),
  write_compiled_modules(Rest).

% Match (or emit) an entire list of characters verbatim.
all_chars([]) --> [].
all_chars([C | Cs]) --> [C], all_chars(Cs).

output_path(OutputPath) -->
  all_chars(OutputPrefix),
  ".sl",
  { append(OutputPrefix, ".js", OutputPath) }.
