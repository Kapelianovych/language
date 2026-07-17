:- module(prelude, [prelude_results/1]).

% End-to-end tests for the implicit prelude that `compiler:compile/4` always
% seeds (`libraries/Std.sl`, see `implicit_prelude_paths/1`).  Exercises the
% resolver-backed BATCH pipeline with an in-memory module table -- `compile/4`'s
% own docs anticipate exactly this ("tests can pass an in-memory fixture
% table") -- over Std.sl's REAL content, so these track the actual prelude file
% rather than a synthetic stand-in.  Every check below passes `PreludePaths =
% []`, so a pass proves the standard library is seeded WITHOUT being asked for.
% `compiler:compile/3` (the resolver-less single-file entry point the golden
% suite uses) is deliberately untouched by the prelude and has no tests here.

:- use_module(library(lists)).
:- use_module(test_harness, [read_file_chars/2]).
:- use_module('../source/compiler', [compile/4, compile/5]).
:- use_module('../source/module_paths', [normalise_path/2]).

% ---------------------------------------------------------------------------
% The in-memory module table: Std.sl's real content, plus small synthetic
% consumer files exercising one aspect of the prelude each.
% ---------------------------------------------------------------------------

consumer("flat.sl", "public main = identity(1)").
consumer("custom_std/Std.sl", "public shout = (x) x").
consumer("custom.sl", "public main = shout(1)").
consumer("pattern.sl", "public main = match None | Some(_) => 1 | None => 2").
consumer("qualified.sl", "public main = Optional.isSome(None)").
consumer("shadow_value.sl", "public identity = (x) x").
consumer("shadow_type.sl", "public type Optional = Foo").
consumer("depth/two/deep.sl", "public main = identity(1)").

resolve_fixture("libraries/Std.sl", Source) :- !, read_file_chars("libraries/Std.sl", Source).
resolve_fixture(Path, Source) :- consumer(Path, Source).

% ---------------------------------------------------------------------------
% Checks.
% ---------------------------------------------------------------------------

prelude_results(Results) :-
  findall(Result, prelude_check(Result), Results).

prelude_check(result('flat prelude value with no import', Status)) :-
  compile_with_prelude("flat.sl", Outcome),
  ( Outcome = compiled(Modules) ->
      ( entry_js_contains(Modules, "flat.sl", "($identity)(") -> Status = pass
      ; Status = fail(no_call_to_identity) )
  ; Status = fail(Outcome) ).

prelude_check(result('bare constructor pattern with no import', Status)) :-
  compile_with_prelude("pattern.sl", Outcome),
  ( Outcome = compiled(_) -> Status = pass ; Status = fail(Outcome) ).

prelude_check(result('unqualified companion-module access (Optional.isSome)', Status)) :-
  compile_with_prelude("qualified.sl", Outcome),
  ( Outcome = compiled(Modules) ->
      % `Optional` now crosses the file boundary as one record value, so
      % `Optional.isSome` is ordinary field access, not a flattened name.
      ( entry_js_contains(Modules, "qualified.sl", "(($Optional)[\"isSome\"])(") -> Status = pass
      ; Status = fail(no_call_to_optional_isSome) )
  ; Status = fail(Outcome) ).

prelude_check(result('local value shadows prelude value', Status)) :-
  compile_with_prelude("shadow_value.sl", Outcome),
  ( Outcome = compiled(_) -> Status = pass ; Status = fail(Outcome) ).

prelude_check(result('local type colliding with prelude type still errors', Status)) :-
  compile_with_prelude("shadow_type.sl", Outcome),
  ( Outcome = threw(analysis_error(duplicate_type_declaration(_))) -> Status = pass
  ; Status = fail(Outcome) ).

prelude_check(result('relative specifier at depth (../../library/Std.js)', Status)) :-
  compile_with_prelude("depth/two/deep.sl", Outcome),
  ( Outcome = compiled(Modules) ->
      ( entry_js_contains(Modules, "depth/two/deep.sl", "from \"../../libraries/Std.js\"") -> Status = pass
      ; Status = fail(wrong_specifier) )
  ; Status = fail(Outcome) ).

prelude_check(result('relative specifier at the prelude\'s own directory (./Std.js)', Status)) :-
  compile_with_prelude("flat.sl", Outcome),
  ( Outcome = compiled(Modules) ->
      ( entry_js_contains(Modules, "flat.sl", "from \"./libraries/Std.js\"") -> Status = pass
      ; Status = fail(wrong_specifier) )
  ; Status = fail(Outcome) ).

% `compile/5` lets a host (the CLI, via SL_HOME) pass a RESOLVED implicit
% prelude instead of the cwd-relative `libraries/Std.sl` default.  The custom
% prelude must REPLACE the default -- `custom.sl` uses only `shout` from it,
% and would fail with `missing_module(libraries/Std.sl)` if the default were
% still seeded, since the fixture table has no entry for it.
prelude_check(result('compile/5 honors a host-resolved implicit prelude', Status)) :-
  ( catch(compile("custom.sl", prelude:resolve_fixture, ["custom_std/Std.sl"], [], Modules),
          Error, Outcome = threw(Error)) ->
      ( var(Outcome) -> Outcome = compiled(Modules) ; true )
  ; Outcome = bare_failure ),
  ( Outcome = compiled(Ms) ->
      ( entry_js_contains(Ms, "custom.sl", "($shout)(") -> Status = pass
      ; Status = fail(no_call_to_shout) )
  ; Status = fail(Outcome) ).

% ---------------------------------------------------------------------------
% Helpers.
% ---------------------------------------------------------------------------

compile_with_prelude(EntryPath, Outcome) :-
  ( catch(compile(EntryPath, prelude:resolve_fixture, [], Modules), Error, Outcome = threw(Error)) ->
      ( var(Outcome) -> Outcome = compiled(Modules) ; true )
  ; Outcome = bare_failure ).

entry_js_contains(Modules, EntryPath, Needle) :-
  normalise_path(EntryPath, Entry),
  memberchk(Entry - Js, Modules),
  sublist(Needle, Js).

sublist(Needle, Haystack) :-
  append(_Prefix, Rest, Haystack),
  append(Needle, _Suffix, Rest), !.
