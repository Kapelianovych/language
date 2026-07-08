:- module(test_harness, [
     report/1,
     read_file_chars/2,
     write_file_chars/2,
     sl_fixtures/2
   ]).

/* A tiny, dependency-free test harness for the compiler. Scryer 0.10 ships no
   plunit, so suites don't hand goals to a runner (that would run them in the
   wrong module); instead each suite computes its own list of

   result(NameAtom, pass) | result(NameAtom, fail(Reason))

   terms and hands them here. `report/1` prints them, tallies pass/fail, and
   `halt/1`s with a non-zero exit code on any failure so CI can gate on it. */

:- use_module(library(pio)).       % phrase_from_file/2, phrase_to_file/2
:- use_module(library(lists)).
:- use_module(library(files)).     % directory_files/2
:- use_module(library(dcgs)).

% ---------------------------------------------------------------------------
% Reporting.
% ---------------------------------------------------------------------------

%% report(+Suites).
%
% Suites is a list of `suite(Title, Results)`.  Prints every check, a summary
% line, then halts (0 if all passed, 1 otherwise).
report(Suites) :-
  report_suites(Suites, 0-0, Pass-Fail),
  nl,
  format("~w passed, ~w failed~n", [Pass, Fail]),
  ( Fail =:= 0 -> halt(0) ; halt(1) ).

report_suites([], Acc, Acc).
report_suites([suite(Title, Results) | Rest], Acc0, Acc) :-
  format("~n~w~n", [Title]),
  report_results(Results, Acc0, Acc1),
  report_suites(Rest, Acc1, Acc).

report_results([], Acc, Acc).
report_results([result(Name, pass) | Rest], P0-F0, Acc) :-
  format("  ok    ~w~n", [Name]),
  P1 is P0 + 1,
  report_results(Rest, P1-F0, Acc).
report_results([result(Name, fail(Reason)) | Rest], P0-F0, Acc) :-
  format("  FAIL  ~w~n          ~q~n", [Name, Reason]),
  F1 is F0 + 1,
  report_results(Rest, P0-F1, Acc).

% ---------------------------------------------------------------------------
% Filesystem helpers.  All paths and file contents are cons lists of character
% atoms (Scryer's default `double_quotes` flag is `chars`).
% ---------------------------------------------------------------------------

%% read_file_chars(+Path, -Chars).
%
% Read a file into a canonical cons list of character atoms.  FAILS (does not
% throw) when the file cannot be read, so callers decide how to report it.
read_file_chars(Path, Chars) :-
  catch(phrase_from_file(all_chars(Raw), Path), _, fail),
  % `phrase_from_file` yields a partial-string-backed list; force a plain cons
  % list so `==/2` against freshly built lists behaves (see module_paths.pl).
  force_list(Raw, Chars).

%% write_file_chars(+Path, +Chars).
write_file_chars(Path, Chars) :-
  phrase_to_file(all_chars(Chars), Path).

%% sl_fixtures(+Dir, -Names).
%
% The basenames of every `*.sl` file directly in Dir, sorted.  Dir is resolved
% relative to the current working directory (run the suite from the repo root).
sl_fixtures(Dir, Names) :-
  directory_files(Dir, Entries),
  findall(Name, ( member(Name, Entries), append(_, ".sl", Name) ), Matching),
  sort(Matching, Names).

force_list([], []).
force_list([C | Cs], [C | Fs]) :- force_list(Cs, Fs).

% Match or emit a list of characters verbatim.
all_chars([]) --> [].
all_chars([C | Cs]) --> [C], all_chars(Cs).
