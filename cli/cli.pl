:- module(cli, [compile_file/2]).

/*  cli/cli.pl  --  The imperative shell around the pure compiler core.

    Everything here touches the real filesystem or a terminal: reading `.sl`
    source, writing `.js` output, and printing errors to `stderr`.  The
    compiler itself (`source/compiler.pl`) never does any of this -- it is
    handed a resolver closure and returns data -- so this is the ONE place
    that wiring happens for a batch, on-disk build.  An LSP or a future
    browser/Node embedding supplies its own I/O instead of loading this file.
*/

:- use_module(library(pio)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(error)).
:- use_module('../source/compiler', [compile/4]).
:- use_module('../source/module_paths', [read_source_chars/2, source_to_js_path/2]).
:- use_module('../source/diagnostics', [message_text/2, reason_text/2]).

%% compile_file(+SourcePath, +PreludePaths).
%
% Compiles the `.sl` file at SourcePath together with every module it imports
% (directly or transitively), writing each module's JavaScript alongside it
% with a `.js` extension.  `PreludePaths` is forwarded to `compiler:compile/4`
% verbatim -- ADDITIONAL `.sl` paths beyond the always-implicit standard
% library (see `compile/4`'s doc) whose public names are implicitly in scope,
% with no `use`, in every module this compiles that is not itself one of them.
% The entry path must end in `.sl`; any other path raises
% domain_error(sl_source_file, SourcePath).
%
% This is the IMPERATIVE SHELL around the pure core: `compiler:compile/4`
% reads sources only through the resolver we pass it (here the filesystem,
% `module_paths:read_source_chars/2`) and returns the generated JavaScript
% instead of writing it.  All filesystem output happens below, and only after
% the WHOLE graph compiled cleanly -- a failed compile therefore never leaves
% partially updated `.js` files behind.  Callers that hold sources elsewhere
% (an editor buffer, a test fixture) call `compiler:compile/4` directly with
% their own resolver, and are free to ignore the returned artifacts entirely
% (check-only).
%
% This is also the CLI entry, so a compilation error is not rethrown raw: it
% is PRINTED to standard error as the same human-readable message the LSP
% shows (see `source/diagnostics.pl`), and compile_file FAILS.  Callers that
% want the `analysis_error` term itself use `compiler:compile/4`.
compile_file(SourcePath, PreludePaths) :-
  % Check the extension first so a wrong one fails fast and loudly.
  ( phrase(output_path(_OutputPath), SourcePath) ->
      true
  ; atom_chars(SourceAtom, SourcePath),
    domain_error(sl_source_file, SourceAtom)
  ),
  catch(
    compile(SourcePath, module_paths:read_source_chars, PreludePaths, CompiledModules),
    analysis_error(Reason),
    ( print_analysis_error(Reason), fail )
  ),
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

% ---------------------------------------------------------------------------
% CLI reporting
% ---------------------------------------------------------------------------

%% print_analysis_error(+Reason).
%
% Write an `analysis_error` payload to standard error as one or more
% human-readable lines.  Syntax errors carry a char-offset span; when the
% offending module's source is readable the offset is shown as `line:column`
% (1-based), otherwise as a raw offset.  Always succeeds.
print_analysis_error(syntax_errors(Module, Diagnostics)) :- !,
  ( read_source_chars(Module, Text) -> true ; Text = none ),
  print_syntax_diagnostics(Diagnostics, Module, Text).
print_analysis_error(syntax_errors(Diagnostics)) :- !,
  print_syntax_diagnostics(Diagnostics, none, none).
print_analysis_error(Reason) :-
  reason_text(Reason, Msg),
  format(user_error, "error: ~s~n", [Msg]).

print_syntax_diagnostics([], _Module, _Text).
print_syntax_diagnostics([diagnostic(Start, _End, What) | Diagnostics], Module, Text) :-
  message_text(What, Msg),
  ( Text \== none, offset_line_column(Text, Start, Line, Column) ->
      format(user_error, "~s:~d:~d: error: ~s~n", [Module, Line, Column, Msg])
  ; Module \== none ->
      format(user_error, "~s: error at offset ~d: ~s~n", [Module, Start, Msg])
  ; format(user_error, "error at offset ~d: ~s~n", [Start, Msg])
  ),
  print_syntax_diagnostics(Diagnostics, Module, Text).

% A char offset as a 1-based line:column position within the source text.
offset_line_column(Text, Offset, Line, Column) :-
  offset_line_column_(Text, Offset, 1, 1, Line, Column).

offset_line_column_(_Text, 0, Line, Column, Line, Column) :- !.
offset_line_column_([], _Remaining, Line, Column, Line, Column) :- !.
offset_line_column_([Ch | Cs], Remaining, Line0, Column0, Line, Column) :-
  Remaining1 is Remaining - 1,
  ( Ch == '\n' -> Line1 is Line0 + 1, Column1 = 1
  ; Line1 = Line0, Column1 is Column0 + 1
  ),
  offset_line_column_(Cs, Remaining1, Line1, Column1, Line, Column).
