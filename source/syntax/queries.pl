:- module(queries, [
  init_db/0, set_input/2, query/2,
  reset_exec_log/0, exec_count/2
]).

/*  source/syntax/queries.pl  --  Demand-driven (query-based) analysis engine.
    ========================================================================

    This is the incremental-analysis layer an LSP needs: type-checking and
    diagnostics that, after an edit, recompute ONLY what the edit affected.
    The design is the one rust-analyzer (Salsa) / Roslyn use, implemented here
    in Prolog over the lossless parser in this directory.

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
:- use_module(library(iso_ext), [setup_call_cleanup/3]).
:- use_module('lexer',  [tokenize/2]).
:- use_module('parser', [parse_tokens/3]).
:- use_module('lower',  [lower/2, parse_source/2]).
:- use_module('../analyser', [analyse_accumulating/6]).
:- use_module('../module_paths', [
  read_source_chars/2,
  canonical_chars/2,
  module_directory/2,
  resolve_source_path/3
]).
:- use_module('../namespace_import', [
  namespace_of/2,
  seed_namespace/9,
  collapse_namespace_access/4
]).
:- use_module('../transformation/macro_program', [process_macros/3]).

% ---------------------------------------------------------------------------
% Database state (all dynamic).
% ---------------------------------------------------------------------------
:- dynamic(current_revision/1).
:- dynamic(input/3).                 % input(Key, Value, ChangedAtRevision)
:- dynamic(memo/5).                  % memo(Key, Value, Deps, VerifiedAt, ChangedAt)
:- dynamic(comp_stack/1).            % comp_stack(ListOfCurrentlyComputingKeys)
:- dynamic(dep_edge/2).              % dep_edge(ParentKey, ChildKey)
:- dynamic(exec_log/1).              % exec_log(Key) -- one per actual recompute
:- dynamic(resolving_dependency/1).  % import-cycle guard (see dependency_interface/2)
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

%% set_input(+Key, +Value).  Records an input and ticks the revision.
set_input(Key, Value) :-
  retract(current_revision(R0)), R is R0 + 1, assertz(current_revision(R)),
  retractall(input(Key, _, _)),
  assertz(input(Key, Value, R)).

% ---------------------------------------------------------------------------
% The query driver.
% ---------------------------------------------------------------------------

%% query(+Key, -Value).
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
  ( memo(Key, V, Deps, Verified, Changed) ->
      ( Verified =:= R ->
          Value = V                                   % step 1: fresh this revision
      ; deps_unchanged_since(Deps, Verified) ->
          % step (a): still valid -- re-stamp verified, keep value & changed_at.
          retract(memo(Key, V, Deps, Verified, Changed)),
          assertz(memo(Key, V, Deps, R, Changed)),
          Value = V
      ; recompute(Key, R, V, Changed, Value)          % steps (b)/(c)
      )
  ; recompute_fresh(Key, R, Value)
  ).

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
recompute(Key, R, OldValue, OldChanged, Value) :-
  run_compute(Key, NewValue, NewDeps),
  ( NewValue == OldValue -> NewChanged = OldChanged   % (b) firewall: no propagation
  ; NewChanged = R                                    % (c) value changed at R
  ),
  retractall(memo(Key, _, _, _, _)),
  assertz(memo(Key, NewValue, NewDeps, R, NewChanged)),
  Value = NewValue.

% Recompute a query that has no memo yet (first demand): it changed "now".
recompute_fresh(Key, R, Value) :-
  run_compute(Key, Value, Deps),
  assertz(memo(Key, Value, Deps, R, R)).

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
%   interface(File)      this file's module_interface (its public entries)
%   import_seeds(File)   seed value/type environments built from its imports
%   analysis(File)       analysis(Errors, DefTypes, Interface) for the whole file
%   diagnostics(File)    parse diagnostics ++ type errors
%   type_at(File, Name)  a top-level definition's resolved type (for hover)
%
% Cross-file flow: `import_seeds(A)` reads `interface(B)` for each dependency B
% of A, so editing B re-checks A automatically -- and the value-equality firewall
% means a change to B that does NOT alter its public interface leaves A untouched.
% ===========================================================================

% Source text.  When the file is open in the editor `query/2` returns its INPUT
% directly (the `input(...)` branch) and never reaches here; this clause is the
% fallback that reads an unopened DEPENDENCY from disk.  A file that cannot be
% read yields empty text (-> empty program -> empty interface), so an importer of
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

% Direct file dependencies (resolved paths), excluding the builtin `Compiler`.
compute(module_deps(File), Deps) :-
  query(program_ast(File), program_node(Items)),
  module_directory(File, Directory),
  findall(Dep,
          ( use_dependency_path(Items, Path),
            Path \== "Compiler",
            resolve_source_path(Directory, Path, Dep) ),
          Deps).

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
        -> ( nonvar(Threw) -> Result = macro_error(Threw)
           ; get_assoc(CanonicalFile, ExpandedAsts, Expanded) -> Result = expanded(Expanded)
           ; Result = macro_error(macro_expansion_missing) )
        ;  Result = macro_error(macro_expansion_failed) )
  ; Result = expanded(Ast) ).

% --- macro-expansion helpers ----------------------------------------------

% Enumerate (on backtracking) every imported path, descending into nested
% `module` bodies and `public` wrappers -- mirrors the loader's `use_path/2`.
use_dependency_path(Items, Path) :-
  member(Item, Items),
  use_dependency_path_in_item(Item, Path).
use_dependency_path_in_item(use_node(Path, _Names, _Span), Path).
use_dependency_path_in_item(use_all_node(Path, _Span), Path).
use_dependency_path_in_item(module_node(_Name, Body, _Span), Path) :-
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
% its AST, or one of its dependencies' interfaces -- changes); parsing stays
% incremental within the file via the green tree.
% ===========================================================================

% Build the seed environments for a file from the interfaces of the modules it
% imports.  This mirrors the loader's `resolve_imports`, but reads each
% dependency's interface through `query(interface(Dep))` so the dependency edge
% is recorded (editing a dependency re-checks its importers) and the result is
% memoised.  Seeding is BEST-EFFORT: a name the dependency does not export is
% left unseeded and surfaces as an `unbound_variable` in the importer, rather
% than aborting analysis.  `Bases`/`Members` drive the whole-module-import access
% collapse (`Namespace.member` -> a flat qualified identifier) below.
compute(import_seeds(File), import_seeds(SeedValues, SeedTypes, Bases, Members)) :-
  query(program_ast(File), program_node(Items)),
  module_directory(File, Directory),
  empty_assoc(V0), empty_assoc(T0),
  seed_imports(Items, Directory, V0, T0, SeedValues, SeedTypes, [], Bases, [], Members).

seed_imports([], _Directory, V, T, V, T, Bases, Bases, Members, Members).
seed_imports([use_node(Path, Names, _) | Rest], Directory, V0, T0, V, T, Bases0, Bases, Members0, Members) :-
  Path \== "Compiler", !,                       % the compiler-macro import is not a file
  dependency_interface_of(Directory, Path, module_interface(ValueEntries, TypeEntries)),
  seed_named_imports(Names, ValueEntries, TypeEntries, V0, T0, V1, T1),
  seed_imports(Rest, Directory, V1, T1, V, T, Bases0, Bases, Members0, Members).
seed_imports([use_all_node(Path, _) | Rest], Directory, V0, T0, V, T, Bases0, Bases, Members0, Members) :- !,
  dependency_interface_of(Directory, Path, Interface),
  namespace_of(Path, Namespace),
  seed_namespace(Namespace, Interface, V0, T0, V1, T1, _Renames, MemberNames, _Tags),
  append(MemberNames, Members0, Members1),
  seed_imports(Rest, Directory, V1, T1, V, T, [Namespace | Bases0], Bases, Members1, Members).
seed_imports([_Other | Rest], Directory, V0, T0, V, T, Bases0, Bases, Members0, Members) :-
  seed_imports(Rest, Directory, V0, T0, V, T, Bases0, Bases, Members0, Members).

% Seed each named import across the value, type and constructor namespaces.  A
% name absent from the interface is silently skipped (see above).
seed_named_imports([], _ValueEntries, _TypeEntries, V, T, V, T).
seed_named_imports([Name | Names], ValueEntries, TypeEntries, V0, T0, V, T) :-
  ( member(Name - ValueEntry, ValueEntries) -> put_assoc(Name, V0, ValueEntry, V1) ; V1 = V0 ),
  ( member(Name - TypeEntry, TypeEntries) -> put_assoc(Name, T0, TypeEntry, Ta) ; Ta = T0 ),
  ( member(constructor_key(Name) - ConstructorEntry, TypeEntries) ->
      put_assoc(constructor_key(Name), Ta, ConstructorEntry, T1) ; T1 = Ta ),
  seed_named_imports(Names, ValueEntries, TypeEntries, V1, T1, V, T).

% A dependency's interface, resolved through the query engine.  The
% `resolving_dependency/1` guard breaks IMPORT CYCLES: if we are already
% resolving this dependency higher up the call chain, return an empty interface
% instead of recursing forever (the compiler rejects cycles outright; the editor
% just degrades gracefully).
dependency_interface_of(Directory, Path, Interface) :-
  resolve_source_path(Directory, Path, Dependency),
  ( resolving_dependency(Dependency) ->
      Interface = module_interface([], [])
  ; setup_call_cleanup(
      assertz(resolving_dependency(Dependency)),
      query(interface(Dependency), Interface),
      retract(resolving_dependency(Dependency)))
  ).

% Run the analyser over a whole file, accumulating every type error (it never
% throws on the first).  Reader macros are expanded first (so the analyser sees
% no macro nodes); whole-module-import accesses are then collapsed to flat
% qualified identifiers (so `Math.add` resolves to the seeded `Math.add`).  A
% catch guards against an unexpected throw so one malformed construct cannot take
% the whole editor session down.
compute(analysis(File), analysis(Errors, DefinitionTypes, Interface)) :-
  query(expanded_ast(File), Expansion),
  ( Expansion = expanded(Ast) ->
      query(import_seeds(File), import_seeds(SeedValues, SeedTypes, Bases, Members)),
      collapse_namespace_access(Ast, Bases, Members, ResolvedAst),
      ( catch(analyse_accumulating(ResolvedAst, SeedValues, SeedTypes, Es, Ds, Iface), Reason,
              ( Es = [error_at(span(0, 0), Reason)], Ds = [], Iface = module_interface([], []) ))
        -> Errors = Es, DefinitionTypes = Ds, Interface = Iface
        ;  Errors = [error_at(span(0, 0), analysis_failed)], DefinitionTypes = [],
           Interface = module_interface([], []) )
  ; % Expansion = macro_error(Reason)
    Expansion = macro_error(MacroReason),
    Errors = [error_at(span(0, 0), MacroReason)], DefinitionTypes = [],
    Interface = module_interface([], []) ).

% A PROJECTION of `analysis` to just the module interface.  Importers depend on
% this, not on the full `analysis`, so the firewall holds: a change inside a
% dependency that leaves its public interface equal does NOT advance this query's
% `changed_at`, and the importers are not re-checked.
compute(interface(File), Interface) :-
  query(analysis(File), analysis(_, _, Interface)).

% All diagnostics for a file: parse errors first, then type errors.
compute(diagnostics(File), All) :-
  query(parse(File), parsed(_, ParseDiagnostics)),
  query(analysis(File), analysis(TypeErrors, _, _)),
  append(ParseDiagnostics, TypeErrors, All).

% The resolved type of a top-level definition (for hover); `unknown` if absent.
compute(type_at(File, Name), Type) :-
  query(analysis(File), analysis(_, DefinitionTypes, _)),
  ( member(Name - Type, DefinitionTypes) -> true ; Type = unknown ).
