:- module(golden, [golden_results/1, golden_bless/0]).

% Golden / snapshot tests at the whole-pipeline seam.  For every
% `test/fixtures/golden/NAME.sl` the suite runs `compile/3` (source text -> JS text,
% no filesystem, no module resolver -- so fixtures must be self-contained,
% import-free programs) and asserts the output equals `test/fixtures/golden/NAME.js.expected`.
%
% On a mismatch the actual output is written to `NAME.js.actual` next to the
% expected file so you can `diff` the two.  When output legitimately changes,
% regenerate every expected with:  scryer-prolog test/run.pl -- --bless

:- use_module(library(lists)).
:- use_module(test_harness, [read_file_chars/2, write_file_chars/2, sl_fixtures/2]).
:- use_module('../source/compiler', [compile/3]).

golden_dir("test/fixtures/golden").

% golden_results(-Results).
golden_results(Results) :-
  golden_dir(Dir),
  sl_fixtures(Dir, Names),
  maplist(golden_one(Dir), Names, Results).

golden_one(Dir, SlName, result(NameAtom, Status)) :-
  atom_chars(NameAtom, SlName),
  fixture_paths(Dir, SlName, SlPath, ExpPath, ActualPath),
  ( \+ read_file_chars(SlPath, _) ->
      Status = fail(cannot_read_source)
  ; \+ read_file_chars(ExpPath, _) ->
      Status = fail(no_expected_file(run_with_bless))
  ; read_file_chars(SlPath, Source),
    read_file_chars(ExpPath, Expected),
    ( catch(compile(Source, Actual, _), Error, Outcome = threw(Error)) ->
        ( var(Outcome) -> Outcome = produced(Actual) ; true )
    ;   Outcome = bare_failure
    ),
    golden_verdict(Outcome, Expected, ActualPath, Status)
  ).

golden_verdict(produced(Actual), Expected, _ActualPath, pass) :-
  Actual == Expected, !.
golden_verdict(produced(Actual), _Expected, ActualPath, fail(mismatch(see(A)))) :- !,
  write_file_chars(ActualPath, Actual),
  atom_chars(A, ActualPath).
golden_verdict(threw(Error), _Expected, _ActualPath, fail(compile_threw(Error))) :- !.
golden_verdict(bare_failure, _Expected, _ActualPath, fail(compile_bare_failed)).

% golden_bless.
%
% (Re)generate every `NAME.js.expected` from the current compiler output.
golden_bless :-
  golden_dir(Dir),
  sl_fixtures(Dir, Names),
  maplist(bless_one(Dir), Names).

bless_one(Dir, SlName) :-
  atom_chars(NameAtom, SlName),
  fixture_paths(Dir, SlName, SlPath, ExpPath, _),
  ( read_file_chars(SlPath, Source),
    catch(compile(Source, Actual, _), _, fail) ->
      write_file_chars(ExpPath, Actual),
      format("  blessed ~w~n", [NameAtom])
  ;   format("  SKIP (does not compile) ~w~n", [NameAtom])
  ).

% fixture_paths(+Dir, +SlName, -SlPath, -ExpPath, -ActualPath): join Dir with
% the `.sl` source and its `.js.expected` / `.js.actual` siblings.
fixture_paths(Dir, SlName, SlPath, ExpPath, ActualPath) :-
  append(Stem, ".sl", SlName),
  join(Dir, SlName, SlPath),
  append(Stem, ".js.expected", ExpName), join(Dir, ExpName, ExpPath),
  append(Stem, ".js.actual",   ActName), join(Dir, ActName, ActualPath).

join(Dir, Name, Path) :- append(Dir, ['/' | Name], Path).
