% Test entry point.  Run from the repository root:
%
%     scryer-prolog test/run.pl              # run every suite
%     scryer-prolog test/run.pl -- --bless   # regenerate golden expectations
%
% Fixture directories are resolved relative to the working directory, so the
% repo root is the intended place to run this from.  Exits non-zero if any
% check fails.

:- use_module(library(os)).        % argv/1
:- use_module(library(lists)).
:- use_module(golden,       [golden_results/1, golden_bless/0]).
:- use_module(roundtrip,    [roundtrip_results/1]).
:- use_module(prelude,      [prelude_results/1]).
:- use_module(errors,       [error_results/1]).
:- use_module(test_harness, [report/1]).

:- initialization(main).

main :-
  ( argv(Args), member("--bless", Args) ->
      format("Blessing golden fixtures from current compiler output...~n", []),
      golden_bless,
      halt(0)
  ; golden_results(Golden),
    roundtrip_results(RoundTrip),
    prelude_results(Prelude),
    error_results(Errors),
    report([
      suite('Golden (compile/3 -> .js.expected)', Golden),
      suite('Round-trip (lexer & parser losslessness)', RoundTrip),
      suite('Prelude (compile/4 -> implicit imports)', Prelude),
      suite('Errors (rejected programs throw, never bare-fail)', Errors)
    ])
  ).
