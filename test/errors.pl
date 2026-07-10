:- module(errors, [error_results/1]).

% Regression suite for REJECTED programs: each one must be refused with a
% thrown `analysis_error(Reason)` -- never a bare failure.  A bare failure is
% how "the build exits 1 printing nothing" bugs happen (the CLI catches only
% thrown errors, so a plain `false` leaves it nothing to print); `compile/3`
% and `compile/4` now backstop any bare failure as
% `analysis_error(internal_error)`, and each check below pins the SPECIFIC
% reason so a regression to the generic backstop is also caught.
%
% Uses `compile/3` (single self-contained source, no resolver, no prelude),
% so every program here must trip its error without imports.

:- use_module(library(lists)).
:- use_module('../source/compiler', [compile/3]).

% bad_program(Name, Source, ExpectedReason).
bad_program('duplicate top-level definition',
            "d = 1\nd = 2\n",
            duplicate_definition("d")).
bad_program('duplicate definition in a block',
            "f = (x) {\n  a = 1\n  a = 2\n  a\n}\n",
            duplicate_definition("a")).
bad_program('empty string interpolation',
            "x = '{}'\n",
            malformed_syntax(_)).
bad_program('annotated definition whose value mismatches',
            "x: number = (y) y\n",
            type_mismatch(_, _)).

error_results(Results) :-
  findall(Result, error_check(Result), Results).

error_check(result(Name, Status)) :-
  bad_program(Name, Source, ExpectedReason),
  ( catch(( compile(Source, _Js, _), Outcome = compiled ),
          analysis_error(Reason),
          Outcome = threw(Reason)) ->
      true
  ; Outcome = bare_failure
  ),
  ( Outcome = threw(ExpectedReason) -> Status = pass
  ; Status = fail(Outcome)
  ).
