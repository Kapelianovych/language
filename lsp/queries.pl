:- module(queries, [
  init_db/0,
  set_input/2,
  set_prelude_modules/1,
  query/2,
  hover_at/3,
  reset_exec_log/0,
  exec_count/2
]).

/*  lsp/queries.pl  --  Demand-driven (query-based) analysis engine.
    ========================================================================

    This is the incremental-analysis layer an LSP needs: type-checking and
    diagnostics that, after an edit, recompute ONLY what the edit affected.
    The design is the one rust-analyzer (Salsa) / Roslyn use, implemented here
    in Prolog over the lossless parser in `source/syntax/`.

    THE MODEL

      * INPUTS are set from outside (`set_input/2`) -- here, a file's source
        text, keyed `src(File)`.  Each input remembers the REVISION at which it
        last changed.
      * DERIVED QUERIES are pure functions of inputs and other queries, defined
        by `compute/2` clauses (e.g. `parse(File)`, `type_of(File, Name)`).
        Their results are MEMOISED with the queries they READ (their deps).
      * A global REVISION counter ticks on every `set_input/2`.

    GETTING A QUERY (`query/2`) -- the Salsa algorithm:

      1. If its memo was already verified THIS revision, return it.
      2. Otherwise, recursively bring each DEP up to date and check whether any
         dep CHANGED since we last verified this query.
           - none changed  -> the cached value is still valid: just re-stamp it
             as verified-now and return it (NO recompute).               (a)
           - some changed   -> RECOMPUTE by running `compute/2`, tracking the
             new deps.  Then compare the new value with the old:
               * equal     -> keep the old `changed_at` (the change did NOT
                 propagate -- this is the FIREWALL that stops downstream work). (b)
               * different -> bump `changed_at` to the current revision.      (c)

      (b) is the crucial bit: a whole-file reparse produces a `parse` value that
      is EQUAL to the previous one when the edit did not change the tree (e.g. a
      no-op edit), so `changed_at` does not advance and `analysis`/`diagnostics`
      are reused untouched.  At file granularity, a real source change re-runs
      `analysis`, but `program_ast` consumers downstream still firewall on
      value-equality.

    DEPENDENCY TRACKING

      While a `compute/2` clause runs, every `query/2` it calls is recorded as a
      dependency (via `dep_edge/2` under the currently-computing key, tracked
      with the `comp_stack/1` stack).  No manual dependency declarations.

    The `exec_log/1` counter records each actual recompute (via `exec_count/2`),
    so a caller can observe that an edit triggers only the minimal set of
    recomputations.
*/

% Names in the green tree are char lists (the parser canonicalises token text),
% so "a" etc. below must read as char lists to compare equal to them.
:- set_prolog_flag(double_quotes, chars).

:- use_module(library(lists)).
:- use_module(library(assoc)).
:- use_module(library(charsio), [write_term_to_chars/3, read_from_chars/2]).
:- use_module(library(iso_ext), [setup_call_cleanup/3]).
:- use_module('../source/syntax/lexer',  [tokenize/2]).
:- use_module('../source/syntax/parser', [parse_tokens/3]).
:- use_module('../source/syntax/lower',  [lower/2, parse_source/2]).
:- use_module('../source/syntax/semantic_tokens', [classify/2]).
:- use_module('../source/analyser', [analyse_accumulating/7]).
:- use_module('../source/module_paths', [
  read_source_chars/2,
  canonical_chars/2,
  module_directory/2,
  resolve_source_path/3,
  normalise_path/2
]).
:- use_module('../source/namespace_import', [
  namespace_of/2,
  seed_namespace/9,
  prelude_bases/2,
  collapse_namespace_access/4
]).
:- use_module('../source/transformation/macro_program', [process_macros/3]).
:- use_module('../source/transformation/constructor_pattern', [resolve_bare_constructors/3]).

% ---------------------------------------------------------------------------
% Database state (all dynamic).
% ---------------------------------------------------------------------------
:- dynamic(current_revision/1).
:- dynamic(input/3).                 % input(Key, Value, ChangedAtRevision)
:- dynamic(memo/5).                  % memo(Key, EncodedValue, Deps, VerifiedAt, ChangedAt)
                                      % EncodedValue is Value run through
                                      % `encode_memo_value/2` (see below), NOT
                                      % the natural term -- `assertz/1` cannot
                                      % hold most real parse trees otherwise.
:- dynamic(comp_stack/1).            % comp_stack(ListOfCurrentlyComputingKeys)
:- dynamic(dep_edge/2).              % dep_edge(ParentKey, ChildKey)
:- dynamic(exec_log/1).              % exec_log(Key) -- one per actual recompute
:- dynamic(resolving_dependency/1).  % import-cycle guard (see dependency_exports/2)
:- discontiguous(compute/2).         % compute clauses are interleaved with helpers

init_db :-
  retractall(current_revision(_)), assertz(current_revision(0)),
  retractall(input(_, _, _)),
  retractall(memo(_, _, _, _, _)),
  retractall(comp_stack(_)), assertz(comp_stack([])),
  retractall(dep_edge(_, _)),
  retractall(exec_log(_)),
  retractall(resolving_dependency(_)).

% ---------------------------------------------------------------------------
% Inputs.
% ---------------------------------------------------------------------------

% set_input(+Key, +Value).  Records an input and ticks the revision.
set_input(Key, Value) :-
  retract(current_revision(R0)), R is R0 + 1, assertz(current_revision(R)),
  retractall(input(Key, _, _)),
  assertz(input(Key, Value, R)).

% set_prelude_modules(+Paths).
%
% Configures the engine's PRELUDE: a list of `.sl` source paths (mirroring
% `compiler:compile/4`'s `PreludePaths`) whose public names are
% seeded into `import_seeds` for every file that is not itself one of them,
% with no `use` required (see `effective_prelude_modules/2`,
% `compute(import_seeds(File), ...)`).  This is plain `set_input/2` under the
% key `prelude_modules` -- NOT a bare dynamic fact -- so that
% `module_deps`/`import_seeds`, which read it via `query(prelude_modules, _)`,
% record it as a real dependency: reconfiguring correctly invalidates their
% memos through the same firewalled machinery as any other input change (and
% reconfiguring to an EQUAL list propagates nothing, same as any other input).
set_prelude_modules(Paths) :-
  normalise_each(Paths, Modules),
  set_input(prelude_modules, Modules).

normalise_each([], []).
normalise_each([Path | Paths], [Module | Modules]) :-
  normalise_path(Path, Module),
  normalise_each(Paths, Modules).

% The default when `set_prelude_modules/1` was never called: no prelude.
compute(prelude_modules, []).

% A file's EFFECTIVE prelude set: every configured prelude module, unless the
% file itself IS one of them (mirrors `compiler:effective_preludes/3` --
% prelude files only see each other through an explicit `use`).  Must be
% called from within a `compute/2` body so `query(prelude_modules, _)` is
% recorded as a dependency of the caller.
effective_prelude_modules(File, Effective) :-
  query(prelude_modules, PreludeModules),
  ( memberchk(File, PreludeModules) -> Effective = [] ; Effective = PreludeModules ).

% ---------------------------------------------------------------------------
% The query driver.
% ---------------------------------------------------------------------------

% query(+Key, -Value).
%
% DETERMINISTIC (note the closing `!`): a query has exactly one value, and its
% evaluation has side effects (memoisation, dependency edges).  Without the cut,
% a later failure -- e.g. `CA =< Verified` failing in `deps_unchanged_since/2`,
% which is the SIGNAL to recompute -- would backtrack INTO this call and re-run
% the side-effecting computation, corrupting the memo table.  The cut commits to
% the first (only) solution so failure propagates cleanly upward.
query(Key, Value) :-
  record_dependency(Key),
  ( input(Key, V, _Changed) -> Value = V
  ; derived(Key, Value)
  ),
  !.

% Record Key as a dependency of whatever query is currently being computed.
record_dependency(Key) :-
  comp_stack([Parent | _]), !,
  assertz(dep_edge(Parent, Key)).    % duplicates are removed by sort/2 in run_compute
record_dependency(_Key).             % no enclosing computation: nothing to record

derived(Key, Value) :-
  current_revision(R),
  ( memo(Key, EncodedV, Deps, Verified, Changed) ->
      ( Verified =:= R ->
          decode_memo_value(EncodedV, Value)          % step 1: fresh this revision
      ; deps_unchanged_since(Deps, Verified) ->
          % step (a): still valid -- re-stamp verified, keep value & changed_at.
          % `EncodedV` is copied through untouched -- it is already in its
          % assert-safe encoded form (see `encode_memo_value/2` below), so
          % there is nothing to re-encode here.
          retract(memo(Key, EncodedV, Deps, Verified, Changed)),
          assertz(memo(Key, EncodedV, Deps, R, Changed)),
          decode_memo_value(EncodedV, Value)
      ; decode_memo_value(EncodedV, OldValue),
        recompute(Key, R, OldValue, Changed, Value)   % steps (b)/(c)
      )
  ; recompute_fresh(Key, R, Value)
  ).

% ---------------------------------------------------------------------------
% Memo value encoding.
%
% WHY THIS EXISTS: Scryer's `assertz/1` rejects a single ground term once it
% has more than roughly 500 total nested subterms, raising
% `representation_error(max_arity)` -- NOT an arity-255 problem with any one
% functor (this codebase's `node(Kind, Children)` / `token(Kind, Text, Span)`
% nodes never have more than a handful of arguments each), but a ceiling on
% the TOTAL number of nested compound subterms reachable from one term handed
% to a single `assertz` call. A lossless parse tree nests one such wrapper per
% syntactic construct (every operator, every punctuation token, every bit of
% trivia is its own `node`/`token`), so it blows through that ceiling on any
% real `.sl` file -- confirmed by bisection to fail on files as small as
% ~50 lines, not just large ones like `libraries/Std.sl`. Before this fix,
% `assertz(memo(Key, Value, ...))` stored `Value` (e.g. a whole `parse(File)`
% tree) as a live nested term, so opening almost any real file crashed the
% query engine (and with it, `didOpen`/hover/diagnostics -- the LSP process
% kept running, but that query's `assertz` threw and the request that
% triggered it got no response).
%
% The limit is specifically about NESTED COMPOUND terms of varying functors --
% NOT about flat list length: asserting a whole file's raw source text (a
% single, possibly multi-thousand-character list, via `set_input/2`) has
% never failed here, in any of this file's callers. So rather than storing a
% query's result as a live nested term, render it to its TEXTUAL form (one
% flat character list, however long) with `write_term_to_chars/3`, and store
% THAT. `read_from_chars/2` parses it straight back into the exact original
% term. This is transparent to every `compute/2` clause and every caller of
% `query/2` elsewhere in the codebase: they only ever see the natural,
% decoded term shape, both in and out -- encoding is purely an implementation
% detail of how a value is parked inside a `memo/5` fact.
% ---------------------------------------------------------------------------

% encode_memo_value(+Value, -Chars): render Value to a flat, assert-safe
% character list. `quoted(true)` makes atoms/char-list text read back
% faithfully (e.g. an identifier spelled the same as an operator, or a string
% token's literal text). `write_term_to_chars/3` does not append a
% clause-terminating full stop, but `read_from_chars/2` (a thin wrapper over
% the standard term reader) requires one -- so one is appended here, and
% `decode_memo_value/2` never has to think about it again.
encode_memo_value(Value, Chars) :-
  write_term_to_chars(Value, [quoted(true)], Chars0),
  append(Chars0, " .", Chars).

% decode_memo_value(+Chars, -Value): the inverse of `encode_memo_value/2`.
decode_memo_value(Chars, Value) :-
  read_from_chars(Chars, Value).

% A query is still valid if EVERY dependency, brought up to date, has not
% changed since this query was last verified.
deps_unchanged_since([], _Verified).
deps_unchanged_since([Dep | Deps], Verified) :-
  query(Dep, _),                     % force the dep up to date first
  changed_at(Dep, ChangedAt),
  ChangedAt =< Verified,
  deps_unchanged_since(Deps, Verified).

changed_at(Key, ChangedAt) :-
  ( input(Key, _, C) -> ChangedAt = C
  ; memo(Key, _, _, _, C) -> ChangedAt = C
  ),
  !.

% Recompute an existing (stale) query; apply the value-equality FIREWALL.
% `OldValue` arrives already DECODED (by `derived/2`, the only caller) back to
% its natural term shape, so the `==` comparison below is the ordinary
% structural comparison it always was -- encoding is invisible here too.
recompute(Key, R, OldValue, OldChanged, Value) :-
  run_compute(Key, NewValue, NewDeps),
  ( NewValue == OldValue -> NewChanged = OldChanged   % (b) firewall: no propagation
  ; NewChanged = R                                    % (c) value changed at R
  ),
  encode_memo_value(NewValue, EncodedNewValue),
  retractall(memo(Key, _, _, _, _)),
  assertz(memo(Key, EncodedNewValue, NewDeps, R, NewChanged)),
  Value = NewValue.

% Recompute a query that has no memo yet (first demand): it changed "now".
recompute_fresh(Key, R, Value) :-
  run_compute(Key, Value, Deps),
  encode_memo_value(Value, EncodedValue),
  assertz(memo(Key, EncodedValue, Deps, R, R)).

% Run a compute/2 rule while tracking the queries it reads as dependencies, and
% counting the recompute.
run_compute(Key, Value, Deps) :-
  retractall(dep_edge(Key, _)),
  retract(comp_stack(Stack)), assertz(comp_stack([Key | Stack])),
  compute(Key, Value),
  retract(comp_stack(_)), assertz(comp_stack(Stack)),
  findall(Child, dep_edge(Key, Child), Children0),
  sort(Children0, Deps),
  assertz(exec_log(Key)).

% ---------------------------------------------------------------------------
% Execution log (for the demo): how many times each query kind recomputed.
% ---------------------------------------------------------------------------
reset_exec_log :- retractall(exec_log(_)).

exec_count(Key, Count) :-
  findall(x, exec_log(Key), Xs), length(Xs, Count).

% ===========================================================================
% The concrete queries (the `compute/2` rules).
%
%   src(File)            source text (char list); an open editor buffer is an
%                        INPUT, an unopened dependency is read from disk below
%   parse(File)          parsed(GreenTree, Diagnostics)
%   program_ast(File)    the file lowered to the historical `*_node` AST
%   def_names(File)      list of top-level definition names
%   exports(File)        this file's module_exports (its public entries)
%   import_seeds(File)   seed value/type environments built from its imports
%   analysis(File)       analysis(Errors, DefTypes, Exports) for the whole file
%   diagnostics(File)    parse diagnostics ++ type errors
%   type_at(File, Name)  a top-level definition's resolved type (for hover)
%
% Cross-file flow: `import_seeds(A)` reads `exports(B)` for each dependency B
% of A, so editing B re-checks A automatically -- and the value-equality firewall
% means a change to B that does NOT alter its public exports leaves A untouched.
% ===========================================================================

% Source text.  When the file is open in the editor `query/2` returns its INPUT
% directly (the `input(...)` branch) and never reaches here; this clause is the
% fallback that reads an unopened DEPENDENCY from disk.  A file that cannot be
% read yields empty text (-> empty program -> empty exports), so an importer of
% a missing module simply sees its imported names as unbound.
compute(src(File), Chars) :-
  ( read_source_chars(File, Source) -> Chars = Source ; Chars = [] ).

compute(parse(File), parsed(Tree, Diagnostics)) :-
  query(src(File), Chars),
  tokenize(Chars, Tokens),
  parse_tokens(Tokens, Tree, Diagnostics).

% The whole file lowered to the historical AST.  Recomputed on any edit, but the
% PER-DEFINITION query below firewalls so only changed defs propagate.
compute(program_ast(File), Ast) :-
  query(parse(File), parsed(Green, _)),
  lower(Green, Ast).

compute(def_names(File), Names) :-
  query(program_ast(File), program_node(Items)),
  findall(Name, member(definition_node(identifier_node(Name, _), _, _, _), Items), Names).

% ===========================================================================
% Reader-macro expansion (whole-(sub)program; see transformation/macro_program).
%
% Macros are a whole-program layer -- a file's `@name` may resolve to a macro
% imported from another file -- so expansion runs over the file's DEPENDENCY
% CLOSURE, exactly like the batch compiler, by reusing the loader's
% `process_macros/3`.  It is gated on `ast_has_macros/1` so the common macro-free
% file pays nothing.  The result is `expanded(Ast)` or, when a macro is ill-typed
% / unknown / loops out, `macro_error(Reason)` (surfaced as a diagnostic).
% ===========================================================================

% Direct file dependencies (resolved paths), excluding the builtin `Compiler`
% -- plus an implicit edge on every EFFECTIVE prelude module (see
% `effective_prelude_modules/2`), so editing the prelude, or reconfiguring it
% via `set_prelude_modules/1`, re-checks every file that implicitly depends on
% it, exactly like an explicit dependency would.
compute(module_deps(File), Deps) :-
  query(program_ast(File), program_node(Items)),
  module_directory(File, Directory),
  findall(Dep,
          ( use_dependency_path(Items, Path),
            Path \== "Compiler",
            resolve_source_path(Directory, Path, Dep) ),
          ExplicitDeps),
  effective_prelude_modules(File, EffectivePreludes),
  append(ExplicitDeps, EffectivePreludes, Deps).

% The file's dependency closure, dependencies first, the file itself last
% (the order `process_macros/3` numbers modules in).  Cycle-safe via a visited
% set; querying each `module_deps` records the edges so editing any file in the
% closure re-expands.
compute(module_closure(File), Closure) :-
  closure_walk(File, [], _Visited, [], Closure).

% The macro-expanded AST of a file (module-erased, like the loader's output).
compute(expanded_ast(File), Result) :-
  query(program_ast(File), Ast),
  ( ast_has_macros(Ast) ->
      query(module_closure(File), Order0),
      % Rebuild every closure path as fresh cons cells.  The order comes back
      % through the memo, where a char list can become a partial string;
      % `library(assoc)` (which `process_macros/3` keys by path) compares a
      % partial string and an equal cons list as DIFFERENT, silently losing a key
      % once 3+ modules are in play.  Canonicalising here keeps the keys uniform.
      maplist(canonical_chars, Order0, Order),
      canonical_chars(File, CanonicalFile),
      parsed_asts(Order, ParsedAsts),
      ( catch(process_macros(Order, ParsedAsts, ExpandedAsts), Reason, Threw = Reason)
        -> ( nonvar(Threw) -> macro_error_location(Threw, Span, MacroReason),
                              Result = macro_error(Span, MacroReason)
           ; get_assoc(CanonicalFile, ExpandedAsts, Expanded) -> Result = expanded(Expanded)
           ; Result = macro_error(span(0, 0), macro_expansion_missing) )
        ;  Result = macro_error(span(0, 0), macro_expansion_failed) )
  ; Result = expanded(Ast) ).

% Split a thrown macro error into (Span, Reason).  A macro-invocation error is
% wrapped `analysis_error(at(Span, Reason))` by `transformation/macro.pl` (so it
% points at the `@invocation`); a whole-program macro error (e.g. a duplicate
% macro) is a bare `analysis_error(Reason)` with no span, reported at file start.
macro_error_location(analysis_error(at(Span, Reason)), Span, Reason) :- !.
macro_error_location(analysis_error(Reason), span(0, 0), Reason) :- !.
macro_error_location(Other, span(0, 0), Other).

% --- macro-expansion helpers ----------------------------------------------

% Enumerate (on backtracking) every imported path, descending into nested
% `module` bodies and `public` wrappers -- mirrors the loader's `use_path/2`.
use_dependency_path(Items, Path) :-
  member(Item, Items),
  use_dependency_path_in_item(Item, Path).
use_dependency_path_in_item(use_node(Path, _Names, _Span), Path).
use_dependency_path_in_item(use_all_node(Path, _Span), Path).
use_dependency_path_in_item(module_node(_Name, _Parameters, _Opacity, _Ascription, Body, _Span), Path) :-
  use_dependency_path(Body, Path).
use_dependency_path_in_item(public_node(Inner, _Span), Path) :-
  use_dependency_path_in_item(Inner, Path).

% Post-order DFS: a file is appended AFTER its dependencies, and marked visited
% before recursing so an import cycle terminates.
closure_walk(File, VisitedIn, VisitedOut, OrderIn, OrderOut) :-
  ( memberchk(File, VisitedIn) ->
      VisitedOut = VisitedIn, OrderOut = OrderIn
  ; query(module_deps(File), Deps),
    closure_walk_list(Deps, [File | VisitedIn], VisitedOut, OrderIn, Order1),
    append(Order1, [File], OrderOut) ).

closure_walk_list([], Visited, Visited, Order, Order).
closure_walk_list([Dep | Deps], VisitedIn, VisitedOut, OrderIn, OrderOut) :-
  closure_walk(Dep, VisitedIn, Visited1, OrderIn, Order1),
  closure_walk_list(Deps, Visited1, VisitedOut, Order1, OrderOut).

% Build the path->AST map `process_macros/3` consumes.  We re-parse from source
% with `parse_source/2` (querying `src` so an edit still invalidates) rather than
% reuse the memoised `program_ast`: that is exactly how the batch loader feeds
% `process_macros`, and it sidesteps a Scryer representation hazard -- a memoised
% AST round-trips through `assertz`, which can turn a char list into a partial
% string, and the macro type-check then compares that against the cons-list names
% it seeds and spuriously misses (e.g. `parseItem`).
parsed_asts(Order, ParsedAsts) :-
  empty_assoc(Empty),
  parsed_asts(Order, Empty, ParsedAsts).
parsed_asts([], Acc, Acc).
parsed_asts([File | Rest], AccIn, AccOut) :-
  query(src(File), Chars),
  parse_source(Chars, Ast),
  put_assoc(File, AccIn, Ast, Acc1),
  parsed_asts(Rest, Acc1, AccOut).

% Does the AST contain anything the macro layer must process: a macro
% definition, an `@name` invocation, or a `use Compiler` import?
ast_has_macros(macro_call_node(_, _, _, _)) :- !.
ast_has_macros(macro_definition_node(_, _, _, _)) :- !.
ast_has_macros(use_node(Path, _, _)) :- Path == "Compiler", !.
ast_has_macros(Term) :-
  compound(Term),
  Term =.. [_Functor | Arguments],
  member(Argument, Arguments),
  ast_has_macros(Argument), !.

% ===========================================================================
% Type analysis -- the SINGLE checker.
%
% Rather than maintain a second Hindley-Milner implementation here, the engine
% runs the batch analyser (`analyse_accumulating/6`) per file.  That guarantees
% the editor sees EXACTLY what the compiler sees, with no risk of the two
% checkers drifting apart.  The analyser is whole-program, so type-checking is
% incremental at FILE granularity (a file is re-checked when its source -- hence
% its AST, or one of its dependencies' exports -- changes); parsing stays
% incremental within the file via the green tree.
% ===========================================================================

% Build the seed environments for a file from the exports of the modules it
% imports.  This mirrors the loader's `resolve_imports`, but reads each
% dependency's exports through `query(exports(Dep))` so the dependency edge
% is recorded (editing a dependency re-checks its importers) and the result is
% memoised.  Seeding is BEST-EFFORT: a name the dependency does not export is
% left unseeded (so analysis continues) but is ALSO reported as an
% `ImportErrors` entry -- `error_at(UseSpan, name_not_exported(Path, Name))` --
% so the diagnostic points at the `use` and names the module, instead of only
% surfacing later as a generic `unbound_variable` at each use site.
% `Bases`/`Members` drive the whole-module-import access collapse
% (`Namespace.member` -> a flat qualified identifier) below.
%
% The file's EFFECTIVE prelude modules (see `effective_prelude_modules/2`)
% are seeded FIRST, into `V0`/`T0`, exactly like `compiler:resolve_imports`
% seeds them before the file's own `Items` -- so an explicit `use` or a local
% declaration of the same name overrides a prelude entry, same as today.  Each
% is seeded with an EMPTY namespace (`namespace_import:qualify/3`), so a flat
% prelude name resolves unqualified and a qualified companion-module name
% (`Optional.isSome`, already dotted in the prelude's own exports) needs
% only `prelude_bases/2`'s derived tokens in `Bases` for the access collapse
% below to recognise it -- no `Std.`-style prefix to strip.
compute(import_seeds(File), import_seeds(SeedValues, SeedTypes, Bases, Members, ImportErrors)) :-
  query(program_ast(File), program_node(Items)),
  module_directory(File, Directory),
  empty_assoc(V0), empty_assoc(T0),
  effective_prelude_modules(File, EffectivePreludes),
  seed_prelude_modules(EffectivePreludes, V0, T0, V1, T1, [], PreludeBases, [], PreludeMembers),
  seed_imports(Items, Directory, V1, T1, SeedValues, SeedTypes, PreludeBases, Bases, PreludeMembers, Members, [], ImportErrors).

% Seed the value/type environments from every effective prelude module's
% exports, resolved through the query engine (so editing the prelude
% re-checks every importer). `prelude_exports_of/2` guards against import
% cycles the same way `dependency_exports_of/3` does for explicit imports.
seed_prelude_modules([], V, T, V, T, Bases, Bases, Members, Members).
seed_prelude_modules([PreludeModule | Rest], V0, T0, V, T, Bases0, Bases, Members0, Members) :-
  prelude_exports_of(PreludeModule, Exports),
  seed_namespace([], Exports, V0, T0, V1, T1, _Renames, MemberNames, _Tags),
  prelude_bases(MemberNames, ModuleBases),
  append(MemberNames, Members0, Members1),
  append(ModuleBases, Bases0, Bases1),
  seed_prelude_modules(Rest, V1, T1, V, T, Bases1, Bases, Members1, Members).

% Like `dependency_exports_of/3`, but the prelude module's path is already
% fully resolved (not relative to some importer's `Directory`), so there is no
% `resolve_source_path` step.
prelude_exports_of(PreludeModule, Exports) :-
  ( resolving_dependency(PreludeModule) ->
      Exports = module_exports([], [])
  ; setup_call_cleanup(
      assertz(resolving_dependency(PreludeModule)),
      query(exports(PreludeModule), Exports),
      retract(resolving_dependency(PreludeModule)))
  ).

seed_imports([], _Directory, V, T, V, T, Bases, Bases, Members, Members, Errors, Errors).
seed_imports([use_node(Path, Names, Span) | Rest], Directory, V0, T0, V, T, Bases0, Bases, Members0, Members, E0, E) :-
  Path \== "Compiler", !,                       % the compiler-macro import is not a file
  dependency_exports_of(Directory, Path, module_exports(ValueEntries, TypeEntries)),
  seed_named_imports(Names, Path, Span, ValueEntries, TypeEntries, V0, T0, V1, T1, E0, E1),
  seed_imports(Rest, Directory, V1, T1, V, T, Bases0, Bases, Members0, Members, E1, E).
seed_imports([use_all_node(Path, _) | Rest], Directory, V0, T0, V, T, Bases0, Bases, Members0, Members, E0, E) :- !,
  dependency_exports_of(Directory, Path, Exports),
  namespace_of(Path, Namespace),
  seed_namespace(Namespace, Exports, V0, T0, V1, T1, _Renames, MemberNames, _Tags),
  append(MemberNames, Members0, Members1),
  seed_imports(Rest, Directory, V1, T1, V, T, [Namespace | Bases0], Bases, Members1, Members, E0, E).
seed_imports([_Other | Rest], Directory, V0, T0, V, T, Bases0, Bases, Members0, Members, E0, E) :-
  seed_imports(Rest, Directory, V0, T0, V, T, Bases0, Bases, Members0, Members, E0, E).

% Seed each named import across the value, type and constructor namespaces.  A
% name in NONE of them is left unseeded and recorded as a `name_not_exported`
% error at the `use`'s span (see the `import_seeds` note above).
seed_named_imports([], _Path, _Span, _ValueEntries, _TypeEntries, V, T, V, T, E, E).
seed_named_imports([Name | Names], Path, Span, ValueEntries, TypeEntries, V0, T0, V, T, E0, E) :-
  ( member(Name - ValueEntry, ValueEntries) -> put_assoc(Name, V0, ValueEntry, V1), FoundValue = true ; V1 = V0, FoundValue = false ),
  ( member(Name - TypeEntry, TypeEntries) -> put_assoc(Name, T0, TypeEntry, Ta), FoundType = true ; Ta = T0, FoundType = false ),
  ( member(constructor_key(Name) - ConstructorEntry, TypeEntries) ->
      put_assoc(constructor_key(Name), Ta, ConstructorEntry, T1), FoundConstructor = true ; T1 = Ta, FoundConstructor = false ),
  ( ( FoundValue == true ; FoundType == true ; FoundConstructor == true ) ->
      E1 = E0
  ; E1 = [error_at(Span, name_not_exported(Path, Name)) | E0]
  ),
  seed_named_imports(Names, Path, Span, ValueEntries, TypeEntries, V1, T1, V, T, E1, E).

% A dependency's exports, resolved through the query engine.  The
% `resolving_dependency/1` guard breaks IMPORT CYCLES: if we are already
% resolving this dependency higher up the call chain, return an empty exports
% instead of recursing forever (the compiler rejects cycles outright; the editor
% just degrades gracefully).
dependency_exports_of(Directory, Path, Exports) :-
  resolve_source_path(Directory, Path, Dependency),
  ( resolving_dependency(Dependency) ->
      Exports = module_exports([], [])
  ; setup_call_cleanup(
      assertz(resolving_dependency(Dependency)),
      query(exports(Dependency), Exports),
      retract(resolving_dependency(Dependency)))
  ).

% Run the analyser over a whole file, accumulating every type error (it never
% throws on the first).  Reader macros are expanded first (so the analyser sees
% no macro nodes); whole-module-import accesses are then collapsed to flat
% qualified identifiers (so `Math.add` resolves to the seeded `Math.add`).  A
% catch guards against an unexpected throw so one malformed construct cannot take
% the whole editor session down.
%
% `HoverEntries` is the analyser's own span-indexed hover index (see
% `source/analyser.pl`'s `analyse_accumulating/7` doc) -- already fully
% resolved and self-contained (`hover_entry(Span, Kind, semantic(Type,
% NamesTable))`), so `compute(hover_index(File), ...)` below only has to
% merge it with the green-tree syntax fallback and this file's own
% diagnostics, not re-derive anything from the AST itself.
compute(analysis(File), analysis(Errors, DefinitionTypes, Exports, HoverEntries)) :-
  query(expanded_ast(File), Expansion),
  ( Expansion = expanded(Ast) ->
      query(import_seeds(File), import_seeds(SeedValues, SeedTypes, Bases, Members, ImportErrors)),
      collapse_namespace_access(Ast, Bases, Members, CollapsedAst),
      % Bare nullary constructor names in match patterns become constructor
      % patterns, so the editor's typing/exhaustiveness matches the compiler's.
      resolve_bare_constructors(CollapsedAst, SeedTypes, ResolvedAst),
      % Import errors (a name not exported by a dependency) lead the list, so the
      % `use`-site diagnostic shows even when the same name later also trips an
      % `unbound_variable` at its use sites.
      ( catch(analyse_accumulating(ResolvedAst, SeedValues, SeedTypes, Es, Ds, Exports, Hs), Reason,
              ( Es = [error_at(span(0, 0), Reason)], Ds = [], Exports = module_exports([], []), Hs = [] ))
        -> append(ImportErrors, Es, Errors), DefinitionTypes = Ds, Exports = Exports, HoverEntries = Hs
        ;  append(ImportErrors, [error_at(span(0, 0), analysis_failed)], Errors), DefinitionTypes = [],
           Exports = module_exports([], []), HoverEntries = [] )
  ; % Expansion = macro_error(Span, Reason) -- Span points at the offending
    % `@invocation` (file start for a whole-program macro error).
    Expansion = macro_error(MacroSpan, MacroReason),
    Errors = [error_at(MacroSpan, MacroReason)], DefinitionTypes = [],
    Exports = module_exports([], []), HoverEntries = [] ).

% A PROJECTION of `analysis` to just the module exports.  Importers depend on
% this, not on the full `analysis`, so the firewall holds: a change inside a
% dependency that leaves its public exports equal does NOT advance this query's
% `changed_at`, and the importers are not re-checked.
compute(exports(File), Exports) :-
  query(analysis(File), analysis(_, _, Exports, _)).

% All diagnostics for a file: parse errors first, then type errors.
compute(diagnostics(File), All) :-
  query(parse(File), parsed(_, ParseDiagnostics)),
  query(analysis(File), analysis(TypeErrors, _, _, _)),
  append(ParseDiagnostics, TypeErrors, All).

% The legacy name query remains useful to small clients, but hover itself is
% span-indexed below.  In particular, a name is not a stable identity in a
% lexically-scoped language, so new callers must use hover_at/3.
compute(type_at(File, Name), Type) :-
  query(analysis(File), analysis(_, DefinitionTypes, _, _)),
  ( member(Name - Type, DefinitionTypes) -> true ; Type = unknown ).

% hover_at(+File, +Offset, -Hover) is the public, offset-based hover contract.
% Keeping the index as a query matters for incremental invalidation: an edit
% changes parse/analysis, and only then replaces the derived entries, never a
% mutable editor-side cache.
hover_at(File, Offset, Hover) :- query(hover_at(File, Offset), Hover).

compute(hover_at(File, Offset), Hover) :-
  query(node_at(File, Offset), Node),
  ( Node = found(_, _, token(Kind, _, _)), trivia_kind(Kind) -> Hover = none
  ; Node = found(_, _, token(missing, _, _)) -> Hover = none
  ; query(hover_index(File), Entries),
    ( smallest_hover(Offset, Entries, Hover) -> true ; Hover = none )
  ).

% `hover_index/1` deliberately starts with the green tree, not the lowered
% AST.  Lowering discards punctuation, while the lossless tree gives every
% meaningful node and token a future-proof fallback.  The analyser's own
% span-indexed `HoverEntries` (see `analysis/1`'s doc above) are overlaid on
% top and win at an equal span (see `hover_priority/2`) -- these already
% cover every expression result, identifier use, binding, pattern, call,
% declaration, and annotation the analyser walks (recorded via `hover_note/5`
% in `infer.pl`/`type_environment.pl`, resolved once in
% `analyser.pl`'s `finalize_raw_hover_entries/3`), so this predicate no
% longer re-derives anything from the AST itself the way the old
% `ast_semantic_entries/3` walk did (name-based, top-level-only, and blind
% to shadowing).
compute(hover_index(File), Entries) :-
  query(parse(File), parsed(Tree, ParseDiagnostics)),
  syntax_hover_entries(Tree, SyntaxEntries),
  query(analysis(File), analysis(TypeErrors, _DefinitionTypes, _, SemanticEntries)),
  diagnostic_hover_entries(ParseDiagnostics, ParseEntries),
  diagnostic_hover_entries(TypeErrors, TypeEntries),
  append(SyntaxEntries, SemanticEntries, E1),
  append(E1, ParseEntries, E2),
  append(E2, TypeEntries, Entries).

trivia_kind(whitespace).
trivia_kind(comment).
trivia_kind(eof).

smallest_hover(Offset, Entries, BestPayload) :-
  findall(candidate(Width, Priority, Payload),
          ( member(hover_entry(span(S, E), _Kind, Payload), Entries),
            Offset >= S, Offset < E, Width is E - S,
            hover_priority(Payload, Priority) ),
          Candidates),
  Candidates \== [],
  best_candidate(Candidates, candidate(_, _, BestPayload)).

% Prefer an error at a shared span, then semantic data, then syntax help.  The
% width comparison comes first, so a token's concise syntax help remains more
% useful than an enclosing expression's broad type.
hover_priority(error(_), 3).
hover_priority(semantic(_, _), 2).
hover_priority(syntax(_, _), 1).

best_candidate([C | Cs], Best) :- best_candidate(Cs, C, Best).
best_candidate([], Best, Best).
best_candidate([candidate(W, P, X) | Cs], candidate(BW, BP, BX), Best) :-
  ( ( W < BW ; W =:= BW, P > BP ) -> Next = candidate(W, P, X) ; Next = candidate(BW, BP, BX) ),
  best_candidate(Cs, Next, Best).

syntax_hover_entries(Tree, Entries) :- syntax_entries(Tree, Entries).
syntax_entries(t(Kind, Text, S, E), Entries) :- !,
  ( trivia_kind(Kind) ; Kind == missing ; S =:= E -> Entries = []
  ; token_help(Kind, Text, Help) -> Entries = [hover_entry(span(S, E), Kind, syntax(Kind, Help))]
  ; Entries = [] ).
syntax_entries(node(Kind, Children), Entries) :- !,
  significant_span(node(Kind, Children), Span),
  syntax_children_entries(Children, ChildEntries),
  ( Span = span(S, E), S < E, node_help(Kind, Help) -> Entries = [hover_entry(Span, Kind, syntax(Kind, Help)) | ChildEntries]
  ; Entries = ChildEntries ).
syntax_entries(_, []).
syntax_children_entries([], []).
syntax_children_entries([C | Cs], Entries) :-
  syntax_entries(C, E1), syntax_children_entries(Cs, E2), append(E1, E2, Entries).

% Bespoke node help: one short sentence for the grammar constructs whose
% shape isn't self-evident. Node kinds with no clause here simply produce no
% hover entry (the node's children still do) -- there is deliberately no
% generic filler text, since "Syntax: identifier." teaches nothing a reader
% doesn't already know.
node_help(function_type, "Function type: `(Param ..): Return`.").
node_help(quantified_type, "Quantified (generic) type: `<A ..> Body`.").
node_help(intersection_type, "Intersection type: satisfies every listed member (`A + B`).").
node_help(type_record, "Anonymous record type: `(label: Type ..)`.").
node_help(type_name, "Named type reference, optionally applied to type arguments (`Name<Arg ..>`).").
node_help(type_param, "Type parameter, optionally bounded (`A` or `A: Bound`).").
node_help(type_param_kind, "Higher-kinded type parameter's arity: `<_ ..>` counts its own type arguments.").
node_help(type_params, "A declaration's or function's type parameter list (`<A B ..>`).").
node_help(type_apply, "Explicit type application at a call site (`f<Type ..>(..)`).").
node_help(type_args, "Explicit type argument list at a call site (`<Type ..>`).").
node_help(record_pattern, "Record (destructuring) pattern: `(label: Pattern ..)`.").
node_help(constructor_pattern, "Constructor pattern: matches a tagged-union case.").
node_help(labeled_pattern, "A labeled member inside a record pattern.").
node_help(literal_pattern, "A literal value pattern (matches only that exact value).").
node_help(wildcard_pattern, "Wildcard pattern `_`: matches anything, binds nothing.").
node_help(binding_pattern, "Binding pattern: matches anything, binds it to a name.").
node_help(module_type, "Module type: a structural or nominal contract for a module's shape.").
node_help(module_type_member, "A module type's declared member.").
node_help(variant, "Tagged-union constructor declaration.").
node_help(function, "Function (lambda) expression.").
node_help(call, "Function call/application.").
node_help(access, "Member access (`target.label` or `target.index`).").
node_help(member, "Accessed member (a label or index).").
node_help(binary, "Binary operator expression.").
node_help(unary, "Unary operator expression.").
node_help(conditional, "Conditional (`if`/`else`) expression.").
node_help(match, "Pattern-matching expression.").
node_help(arm, "A single match arm: pattern, optional guard, and result.").
node_help(guard, "A match arm's guard condition.").
node_help(block, "Block expression: its own nested scope.").
node_help(definition, "Value definition (`name = value`, optionally annotated).").
node_help(ascription, "Type annotation (`: Type`).").
node_help(external, "Foreign (JS) declaration: its type is trusted, not checked.").
node_help(macro_definition, "Reader-macro definition.").
node_help(macro_call, "Reader-macro invocation (`@name(..)`), expanded before type-checking.").
node_help(quote, "Quasiquote: builds an `Ast` value from a syntax template.").
node_help(unquote, "Unquote `~expr`: splices a checked `Ast` expression into a template.").
node_help(spread, "Spread `..value`: splices a record's fields into a new one.").
node_help(placeholder, "Placeholder `_`: a call argument hole, producing a partial application.").
node_help(use, "Import declaration.").
node_help(module, "Module declaration: a record value with its own nested scope.").
node_help(opaque, "Opacity modifier: hides a declaration's structural shape from other names.").
node_help(public, "Export modifier: makes a declaration visible to importers.").
node_help(type_declaration, "Type declaration.").
node_help(type_hole, "Type argument hole `_`: this position is inferred, not supplied.").
node_help(type_label, "A record/module type member's label.").
node_help(type_member, "A record type's declared member.").
node_help(type_rest, "A record type's open-row tail (`..` or `..R`).").
node_help(mutability, "Field mutability modifier (`mutable`, or readonly by default).").
node_help(group, "Parenthesised expression.").
node_help(error, "Malformed syntax (a parse error).").
node_help(program, "The whole source file.").

token_help(ident, Text, Help) :- keyword_help(Text, Help), !.
token_help(ident, _Text, "Identifier.").
token_help(number, _Text, "Number literal.").
token_help(string, _Text, "String literal.").
token_help(underscore, _Text, "Placeholder or wildcard.").
% Bespoke token help, kept only for punctuation/operators whose meaning is
% NOT self-evident from ordinary language experience (overloaded, doubled, or
% otherwise surprising). Plain structural punctuation (`(`, `.`, `=`, ...) and
% conventional arithmetic/comparison operators produce no hover entry -- see
% `syntax_entries/2`'s handling of a failed `token_help/3` lookup.
%
% Kind is an ATOM (the lexer builds it via `atom_chars(Kind, Text)`, see
% lexer.pl) -- NOT a char list, so these heads are quoted atoms despite this
% file's `double_quotes(chars)` flag, unlike every other (string) argument
% in this predicate.
token_help('<', _Text, "Opens a type-parameter/type-argument list, or the less-than operator.").
token_help('>', _Text, "Closes a type-parameter/type-argument list, or the greater-than operator.").
token_help(',', _Text, "Digit-group separator inside a number literal (e.g. `1,000`); this language has no list/argument-separator comma.").
token_help('->', _Text, "Pipe: `x -> f` applies `f` to `x`.").
token_help('+', _Text, "Addition, or an intersection type's `+`.").
% `&&`/`^^`/`||` are the BOOLEAN and/xor/or family; `&`/`^`/`|` below are the
% separate BITWISE family, at lower precedence (see binary_operator/3 in
% parser.pl) -- the doubled spelling is the only thing marking which is which.
token_help('&&', _Text, "Boolean and (bitwise and is `&`).").
token_help('^^', _Text, "Boolean xor (bitwise xor is `^`).").
token_help('||', _Text, "Boolean or (bitwise or is `|`).").
token_help('!', _Text, "Boolean negation (bit inversion is `!!`).").
token_help('!!', _Text, "Bit inversion (boolean negation is `!`).").
token_help('&', _Text, "Bitwise and (boolean and is `&&`).").
token_help('^', _Text, "Bitwise xor (boolean xor is `^^`).").
token_help('|', _Text, "Bitwise or (boolean or is `||`).").
% `~` is NOT bitwise negation (that's `!!`, see above) -- it only introduces
% an unquote, inside or outside a quasiquote.
token_help('~', _Text, "Unquote: `~expr` splices a checked expression into a quasiquote template.").
token_help('`', _Text, "Opens a quasiquote.").
token_help('@', _Text, "Reader-macro invocation prefix.").
keyword_help("if", "Conditional expression.").
keyword_help("else", "Alternative conditional branch.").
keyword_help("match", "Pattern matching expression.").
keyword_help("type", "Type declaration.").
keyword_help("module", "Module declaration.").
keyword_help("use", "Import declaration.").
keyword_help("public", "Public export modifier.").
keyword_help("external", "Foreign declaration.").
keyword_help("macro", "Reader macro declaration.").
keyword_help("opaque", "Nominal visibility modifier.").
keyword_help("mutable", "Mutable field modifier.").
keyword_help("true", "Boolean literal.").
keyword_help("false", "Boolean literal.").

diagnostic_hover_entries([], []).
diagnostic_hover_entries([diagnostic(S, E, Reason) | Rest], [hover_entry(span(S, E), error, error(parse(Reason))) | Entries]) :- !,
  diagnostic_hover_entries(Rest, Entries).
diagnostic_hover_entries([error_at(Span, Reason) | Rest], [hover_entry(Span, error, error(Reason)) | Entries]) :- !,
  diagnostic_hover_entries(Rest, Entries).
diagnostic_hover_entries([_ | Rest], Entries) :- diagnostic_hover_entries(Rest, Entries).

% Semantic-highlighting tokens: an ascending-Start `tok(Type, Start, End)`
% list over the file's green tree (see `syntax/semantic_tokens.pl`).  Depends
% only on `parse`, so it firewalls exactly like `program_ast` -- a
% type-error-only edit (parse tree unchanged) does not recompute this.
compute(semantic_tokens(File), Tokens) :-
  query(parse(File), parsed(Tree, _)),
  classify(Tree, Tokens).

% ===========================================================================
% Node-at-offset -- locate the cursor in the green tree.
%
% Given a 0-based character `Offset`, `node_at(File, Offset)` returns
%
%     found(EnclosingKind, span(NS, NE), Token)
%
% where the ENCLOSING node is the SMALLEST green node whose extent covers the
% offset (its significant span is span(NS,NE)), and `Token` is the leaf the
% cursor sits on: `token(Kind, Text, span(TS, TE))`, or `none` when the offset
% falls in a gap between a node's children.  `none` (the whole result) when the
% offset lies outside the tree.
%
% This is the one piece of infrastructure precise hover, go-to-definition,
% find-references, selection ranges and document highlight all build on: each is
% "locate the cursor, then interpret the node/token found".  Descent uses each
% child's FULL extent (first..last leaf, trivia included) so a click inside
% whitespace still resolves to the enclosing construct; the reported span is the
% SIGNIFICANT one (trivia/`missing` excluded), matching the spans `lower`
% produces elsewhere.
% ===========================================================================
compute(node_at(File, Offset), Result) :-
  query(parse(File), parsed(Tree, _)),
  ( descend(Tree, Offset, Enclosing, Leaf) ->
      Enclosing = node(EnclosingKind, _),
      significant_span(Enclosing, span(NS, NE)),
      ( Leaf = t(TokenKind, Text, TS, TE) ->
          Token = token(TokenKind, Text, span(TS, TE))
      ; Token = none ),
      Result = found(EnclosingKind, span(NS, NE), Token)
  ; Result = none ).

% Descend to the smallest node covering Offset.  `Enclosing` is that node;
% `Leaf` is the covering leaf within it, or `none` if the offset lands in a gap
% between children.  Fails if this node does not cover the offset at all.
descend(node(Kind, Children), Offset, Enclosing, Leaf) :-
  covers(node(Kind, Children), Offset),
  ( covering_child(Children, Offset, Child) ->
      ( Child = node(_, _) ->
          descend(Child, Offset, Enclosing, Leaf)      % a deeper node covers it
      ; Enclosing = node(Kind, Children), Leaf = Child ) % covering leaf: this node is smallest
  ; Enclosing = node(Kind, Children), Leaf = none ).     % offset in an inter-child gap

% The first child whose full extent covers Offset.
covering_child([Child | Rest], Offset, Found) :-
  ( covers(Child, Offset) -> Found = Child ; covering_child(Rest, Offset, Found) ).

% Half-open [Start, End) cover test over a green term's FULL extent, so a
% zero-width `missing` leaf [P,P) never covers and adjacent tokens do not both
% match one offset.
covers(Green, Offset) :-
  full_extent(Green, Start, End),
  Offset >= Start, Offset < End.

% Full extent: earliest leaf start .. latest leaf end (trivia included).  Fails
% on a term with no leaves (only zero-width leaves collapse to Start == End,
% which `covers/2` then rejects).
full_extent(Green, Start, End) :-
  green_leaves(Green, Leaves),
  Leaves = [t(_, _, Start, _) | _],
  last_leaf_end(Leaves, End).

last_leaf_end([t(_, _, _, E)], E) :- !.
last_leaf_end([_ | Rest], E) :- last_leaf_end(Rest, E).

% Significant span: first..last NON-trivia, NON-`missing` leaf (matches `lower`'s
% `gspan`).  Falls back to (0,0) when a node has only trivia/missing leaves.
significant_span(Green, span(Start, End)) :-
  green_leaves(Green, All),
  include_significant(All, Significant),
  ( Significant = [t(_, _, Start, _) | _] ->
      last_leaf_end(Significant, End)
  ; Start = 0, End = 0 ).

include_significant([], []).
include_significant([Leaf | Rest], Out) :-
  ( significant_leaf(Leaf) -> Out = [Leaf | Out1] ; Out = Out1 ),
  include_significant(Rest, Out1).

significant_leaf(t(Kind, _, Start, End)) :-
  Kind \== whitespace, Kind \== comment, Kind \== missing, Start \== End.

% In-order leaves of a green term.
green_leaves(t(K, Tx, S, E), [t(K, Tx, S, E)]) :- !.
green_leaves(node(_, Children), Leaves) :- green_leaves_list(Children, Leaves).

green_leaves_list([], []).
green_leaves_list([Child | Rest], Leaves) :-
  green_leaves(Child, L1), green_leaves_list(Rest, L2), append(L1, L2, Leaves).
