:- module(compiler, [
  compile/3,
  compile/4,
  compile/5
]).

/*  compiler.pl  --  The compiler's public surface: source text or a module
    graph in, JavaScript out.  No filesystem access, no writing, no printing --
    see `cli/cli.pl` for the imperative shell that reads `.sl` files, writes
    `.js` files, and reports errors to a terminal, and `lsp/` for the
    editor-facing incremental front end.  Keeping this module I/O-free is what
    lets any host (a CLI, an LSP, a future browser/Node embedding) reuse the
    same compiler by supplying its own source access and its own use for the
    output.

    TWO ENTRY POINTS

      * `compile/3`  -- a single, self-contained source text (no `use`,
        no module resolution). The golden test suite exercises this directly.
      * `compile/4`  -- an entry module plus a source resolver; resolves the
        whole `use` graph, type-checks every module in dependency order, and
        returns the generated JavaScript per module. See its own doc below.
      * `compile/5`  -- like `compile/4`, but the IMPLICIT prelude paths (the
        standard library) are passed by the host instead of defaulting to the
        cwd-relative `libraries/Std.sl` -- a host that can be launched from
        anywhere (the CLI) resolves where the standard library actually lives
        and passes it here.
*/

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(assoc)).
:- use_module('syntax/lower', [parse_source/3]).
:- use_module(analyser, [analyse/2, analyse_module/5]).
:- use_module(generator, [generate/2]).
:- use_module(module_paths, [
  normalise_path/2,
  module_directory/2,
  resolve_source_path/3,
  relative_specifier/3
]).
:- use_module(namespace_import, [
  namespace_of/2,
  seed_namespace/9,
  prelude_bases/2,
  collapse_namespace_access/4,
  rewrite_constructor_tags/3
]).
:- use_module('transformation/macro', [check_macros/1, expand_macros/2]).
:- use_module('transformation/module', [expand_modules/2]).
:- use_module('transformation/macro_program', [process_macros/3]).
:- use_module('transformation/constructor_pattern', [resolve_bare_constructors/3]).

% ---------------------------------------------------------------------------
% compile/3 -- a single, import-free source text.
% ---------------------------------------------------------------------------

% compile(+Source, -Output, -AnalysisResult).
%
% Compiles source text into output text.  A syntax error is reported as a thrown
% `analysis_error(syntax_errors(Diagnostics))` rather than a silent failure: the
% recovering parser turns malformed input into `error_node`s that inference would
% otherwise bare-fail on, so we refuse the program up front with its diagnostics.
compile(Source, Output, AnalysisResult) :-
  ( compile_source(Source, Output, AnalysisResult) ->
      true
  ; % Every failure the pipeline can diagnose is THROWN as an
    % `analysis_error`; a bare failure is therefore a compiler bug.  It must
    % still reach the user as an error -- a host that sees a plain `false`
    % has nothing to print, which is how "the build exits saying nothing"
    % happens -- so it is reported as an internal error instead.
    throw(analysis_error(internal_error))
  ).

compile_source(Source, Output, AnalysisResult) :-
  once((
    parse_source(Source, ParsedAst, Diagnostics),
    ( Diagnostics == [] -> true
    ; throw(analysis_error(syntax_errors(Diagnostics)))
    ),
    % Process reader macros (type-check bodies, then expand invocations) before
    % type-checking and generating the resulting program.
    check_macros(ParsedAst),
    expand_macros(ParsedAst, ExpandedAst),
    expand_modules(ExpandedAst, FlatAst),
    % Bare nullary constructor names in match patterns become constructor
    % patterns (no imports here, so only this file's own declarations apply).
    empty_assoc(NoImports),
    resolve_bare_constructors(FlatAst, NoImports, Ast),
    analyse(Ast, AnalysisResult),
    generate(Ast, Output)
  )).

% ---------------------------------------------------------------------------
% compile/4 -- multi-file module loader and build driver.
%
% Given an entry `.sl` file, this resolves the whole import graph, type-checks
% every module in dependency order, and RETURNS the generated JavaScript per
% module -- it performs no filesystem output itself (see `cli/cli.pl`).
%
% Pipeline:
%
%     entry.sl --read_module-->   parse, then `expand_modules` erases nested
%                                  `module`s (so the graph/import scan sees a
%                                  `use` lifted out of a module body)
%              --build_graph-->   modules in topological order (deps first),
%                                  import cycles rejected
%              --per module-->    resolve imports against already-compiled
%                                  dependency interfaces, seed the analyser,
%                                  collapse `namespace.member` accesses,
%                                  resolve bare nullary constructor patterns,
%                                  `analyse_module`, rewrite `use`/`use_all`
%                                  nodes to `import_node`/`namespace_import_node`,
%                                  rewrite imported constructor patterns to
%                                  their intrinsic tags, generate JavaScript
%                                  (returned to the caller, NOT written here)
%
% A MODULE is identified by its normalised absolute-ish source path (a
% character list).  `use ./math:(..)` in a file `Dir/a.sl` refers to the
% module `Dir/math.sl`; the emitted JavaScript imports from `"./math.js"`
% (the relative specifier the programmer wrote, with the extension swapped).
%
% A NAMED import (`use ./math:(a b)`) resolves each listed name across all
% three namespaces from the dependency's exported interface: a value seeds the
% value environment (and is a runtime import), a type seeds the type
% environment, a constructor seeds both.  A name absent from the interface is
% an `unknown_import` error.  A WHOLE-MODULE import (`use ./math`) seeds EVERY
% public entry under a `math.`-qualified local name -- see `namespace_import`.
% ---------------------------------------------------------------------------

% compile(+EntryPath, +ResolveModule, +PreludePaths, -CompiledModules).
%
% Compiles the module graph rooted at `EntryPath` (a `.sl` source path as a
% character list).  `CompiledModules` is a list of `ModulePath - JavaScript`
% pairs in dependency order (dependencies first), each JavaScript a character
% list.
%
% The standard library (`libraries/Std.sl`, see `implicit_prelude_paths/1`) is
% ALWAYS an effective prelude -- callers never need to name it.  `PreludePaths`
% is a caller-supplied list of ADDITIONAL `.sl` source paths whose PUBLIC names
% are likewise seeded into every OTHER module with no `use` at all -- an
% implicit whole-module import with an EMPTY namespace prefix (see
% `namespace_import:qualify/3`), so a flat name like `not` and a qualified
% companion-module name like `Optional.isSome` (already dotted in the
% dependency's own interface, from a nested `public module`) both resolve
% unqualified.  Naming the implicit standard library again in `PreludePaths` is
% harmless (the combined list is deduplicated by normalised path -- see
% `distinct_preserve_order/2`).  A module that is ITSELF one of the effective
% preludes receives no implicit seeding (empty effective prelude set): prelude
% files only see each other through an explicit `use`, which sidesteps any
% question of ordering a mutual implicit dependency between them.
%
% I/O IS INJECTED / RETURNED, NOT PERFORMED HERE.  This predicate touches the
% outside world only through `ResolveModule`; it never writes anything.  The
% split is deliberate (functional core / imperative shell):
%
%   * INPUT is a closure because reading happens MID-ALGORITHM: the graph walk
%     discovers imports while parsing, so the loader must be able to ask for
%     "the source at Path" at arbitrary points.  `call(ResolveModule, Path,
%     Chars)` yields the module source as a character list and FAILS if no such
%     module exists (reported here as `cannot_read_module`).  `cli/cli.pl`
%     passes a filesystem reader (`module_paths:read_source_chars/2`); an
%     editor front-end can pass one that prefers open-buffer contents over
%     what is on disk; tests can pass an in-memory fixture table.
%
%   * OUTPUT is a plain return value because writing has no such constraint:
%     every artifact exists only once the whole graph has compiled. Returning
%     data instead of taking an "emit" closure keeps this predicate pure,
%     trivially testable, and means a failed compile can never leave PARTIAL
%     OUTPUT behind -- the caller (`cli:compile_file/2`) only starts writing
%     after everything type-checked and generated cleanly.
%
%   * CHECK-ONLY MODE therefore needs no flag: a caller that only wants
%     type-checking calls this and ignores `CompiledModules`.  (Codegen still
%     runs, but `generate/2` is a cheap emission pass next to inference --
%     split the loop below only if profiling ever says otherwise.  Note also
%     that `analyse_module` throws on the FIRST error, so this path yields at
%     most one diagnostic; rich multi-diagnostic feedback is the job of the
%     incremental engine in `lsp/queries.pl`, not this batch driver.)
compile(EntryPath, ResolveModule, PreludePaths, CompiledModules) :-
  implicit_prelude_paths(ImplicitPreludePaths),
  compile(EntryPath, ResolveModule, ImplicitPreludePaths, PreludePaths, CompiledModules).

% compile(+EntryPath, +ResolveModule, +ImplicitPreludePaths, +PreludePaths, -CompiledModules).
%
% Like `compile/4`, with the implicit prelude set made explicit:
% `ImplicitPreludePaths` plays the role `implicit_prelude_paths/1` plays for
% `compile/4` (the standard library, seeded into every non-prelude module),
% and `PreludePaths` remains the caller's ADDITIONAL preludes.  This core
% never touches the filesystem, so it cannot know where the standard library
% lives when the process is launched outside the repository -- a host that
% can be (the CLI, via `SL_HOME`) resolves the real path and passes it here.
compile(EntryPath, ResolveModule, ImplicitPreludePaths, PreludePaths, CompiledModules) :-
  ( compile_graph(EntryPath, ResolveModule, ImplicitPreludePaths, PreludePaths, CompiledModules) ->
      true
  ; % Same backstop as `compile/3`: a bare failure anywhere in the graph
    % build is a compiler bug, but the user still gets an error for it.
    throw(analysis_error(internal_error))
  ).

compile_graph(EntryPath, ResolveModule, ImplicitPreludePaths, PreludePaths, CompiledModules) :-
  once((
    normalise_path(EntryPath, Entry),
    append(ImplicitPreludePaths, PreludePaths, AllPreludePaths),
    normalise_paths(AllPreludePaths, AllPreludeModules),
    distinct_preserve_order(AllPreludeModules, PreludeModules),
    empty_assoc(Asts0),
    build_graph(Entry, ResolveModule, [], PreludeModules, Asts0, [], ParsedAsts, OrderReversed),
    reverse(OrderReversed, Order),
    % Reader macros are a WHOLE-PROGRAM compile-time layer: collect every
    % module's macros into one table, type-check them together (so a macro may
    % call one imported from another file), then expand each module against that
    % table.  This runs after the whole graph is parsed and before per-module
    % compilation, so cross-file `@name` uses resolve.
    process_macros(Order, ParsedAsts, Asts),
    empty_assoc(Interfaces0),
    compile_modules(Order, Asts, PreludeModules, Interfaces0, CompiledModules)
  )).

% The standard library is always an effective prelude; see `compile/4`'s doc.
% This default is CWD-RELATIVE, which suits in-repo callers (tests, and the
% CLI when run from the repository root); `compile/5` exists for hosts that
% resolve the standard library's real location themselves.
implicit_prelude_paths(["libraries/Std.sl"]).

normalise_paths([], []).
normalise_paths([Path | Paths], [Normalised | Normalised1]) :-
  normalise_path(Path, Normalised),
  normalise_paths(Paths, Normalised1).

% Drop later duplicates, keeping first-seen order -- so the implicit standard
% library (listed first) wins its position even if a caller also names it.
distinct_preserve_order(List, Distinct) :- distinct_preserve_order(List, [], Distinct).
distinct_preserve_order([], _Seen, []).
distinct_preserve_order([Item | Rest], Seen, Output) :-
  ( memberchk(Item, Seen) -> Output = Output1 ; Output = [Item | Output1] ),
  distinct_preserve_order(Rest, [Item | Seen], Output1).

% A module's EFFECTIVE prelude set: every configured prelude module, unless
% the module itself IS one of them (see the `compile/4` doc).
effective_preludes(Module, PreludeModules, Effective) :-
  ( memberchk(Module, PreludeModules) -> Effective = [] ; Effective = PreludeModules ).

% ---------------------------------------------------------------------------
% Dependency graph (depth-first, post-order => dependencies first)
% ---------------------------------------------------------------------------

% build_graph(+Module, +ResolveModule, +InProgress, +PreludeModules, +AstsIn, +OrderIn, -AstsOut, -OrderOut).
% `InProgress` is the chain of ancestors currently being visited (for cycle
% detection); `Asts` memoises each module's parsed AST (and marks it done);
% `Order` accumulates modules with each placed before its dependencies, so the
% caller reverses it to get dependencies-first order.
build_graph(Module, _ResolveModule, _InProgress, _PreludeModules, AstsIn, OrderIn, AstsOut, OrderOut) :-
  get_assoc(Module, AstsIn, _), !,           % already compiled into the graph
  AstsOut = AstsIn,
  OrderOut = OrderIn.
build_graph(Module, ResolveModule, InProgress, PreludeModules, AstsIn, OrderIn, AstsOut, OrderOut) :-
  read_module(Module, ResolveModule, Ast),
  module_dependencies(Ast, Module, PreludeModules, Dependencies),
  build_graph_dependencies(Dependencies, ResolveModule, [Module | InProgress], PreludeModules, AstsIn, OrderIn, Asts1, Order1),
  put_assoc(Module, Asts1, Ast, AstsOut),
  OrderOut = [Module | Order1].

build_graph_dependencies([], _ResolveModule, _InProgress, _PreludeModules, Asts, Order, Asts, Order).
build_graph_dependencies([Dependency | Dependencies], ResolveModule, InProgress, PreludeModules, AstsIn, OrderIn, AstsOut, OrderOut) :-
  ( memberchk(Dependency, InProgress) ->
      throw(analysis_error(import_cycle(Dependency)))
  ; true
  ),
  build_graph(Dependency, ResolveModule, InProgress, PreludeModules, AstsIn, OrderIn, Asts1, Order1),
  build_graph_dependencies(Dependencies, ResolveModule, InProgress, PreludeModules, Asts1, Order1, AstsOut, OrderOut).

% Read and PARSE a module.  Macro expansion and nested-module erasure happen
% later (in `process_macros`), once the whole graph is known -- a `@name` use
% may resolve to a macro imported from another file, so expansion is a
% whole-program pass, not a per-file one.
read_module(Module, ResolveModule, ParsedAst) :-
  ( call(ResolveModule, Module, Source) ->
      true
  ; throw(analysis_error(cannot_read_module(Module)))
  ),
  parse_source(Source, ParsedAst, Diagnostics),
  % A syntax error anywhere in the graph aborts the build with the offending
  % module and its diagnostics -- otherwise the `error_node`s the recovering
  % parser emits would reach inference and bare-fail with no explanation.
  ( Diagnostics == [] -> true
  ; throw(analysis_error(syntax_errors(Module, Diagnostics)))
  ).

% Dependency scanning runs on the PARSED AST (nested modules not yet lifted), so
% it descends into `module` bodies to find their `use`s.  The builtin `Compiler`
% import is not a file dependency and is skipped.  The module's EFFECTIVE
% prelude set (see `effective_preludes/3`) is appended: an implicit dependency
% edge on every prelude module, so the graph's topological sort compiles them
% before anything that needs their (implicit or explicit) interface.
module_dependencies(program_node(Items), Module, PreludeModules, Dependencies) :-
  module_directory(Module, Directory),
  findall(Dependency,
          ( use_path(Items, Path),
            Path \== "Compiler",
            resolve_source_path(Directory, Path, Dependency) ),
          ExplicitDependencies),
  effective_preludes(Module, PreludeModules, EffectivePreludes),
  append(ExplicitDependencies, EffectivePreludes, Dependencies).

% Enumerate (on backtracking) every imported path in an item list, descending
% into nested `module` bodies and `public` wrappers.
use_path(Items, Path) :-
  member(Item, Items),
  use_path_in_item(Item, Path).

use_path_in_item(use_node(Path, _Names, _Span), Path).
use_path_in_item(use_all_node(Path, _Span), Path).
use_path_in_item(module_node(_Name, Body, _Span), Path) :-
  use_path(Body, Path).
use_path_in_item(public_node(Inner, _Span), Path) :-
  use_path_in_item(Inner, Path).

% ---------------------------------------------------------------------------
% Per-module compilation, in dependency order
% ---------------------------------------------------------------------------

% compile_modules(+Order, +Asts, +PreludeModules, +Interfaces, -CompiledModules).
% Each module's JavaScript is paired with its source path and RETURNED, not
% written -- see the `compile/4` doc for why this stays I/O-free.
compile_modules([], _Asts, _PreludeModules, _Interfaces, []).
compile_modules([Module | Rest], Asts, PreludeModules, InterfacesIn, [Module - JavaScript | Compiled]) :-
  get_assoc(Module, Asts, Ast),
  module_directory(Module, Directory),
  effective_preludes(Module, PreludeModules, EffectivePreludes),
  resolve_imports(Ast, Directory, InterfacesIn, EffectivePreludes, SeedValueEnvironment, SeedTypeEnvironment,
                  PreludePlan, ImportPlan, NamespaceBases, NamespaceMembers, ConstructorTags),
  % Collapse `Namespace.member` value accesses to flat qualified identifiers
  % (using the imported interfaces' member sets) before anything reads the AST.
  collapse_namespace_access(Ast, NamespaceBases, NamespaceMembers, CollapsedAst),
  % Resolve bare nullary constructor names in match patterns (this module's
  % own declarations plus the seeded imports), before the AST forks into the
  % analysis and codegen paths -- both must see the same patterns.
  resolve_bare_constructors(CollapsedAst, SeedTypeEnvironment, ResolvedAst),
  analyse_module(ResolvedAst, SeedValueEnvironment, SeedTypeEnvironment, _Result, Interface),
  put_assoc(Module, InterfacesIn, Interface, Interfaces1),
  rewrite_imports(ResolvedAst, PreludePlan, ImportPlan, CodegenAst0),
  % An imported constructor's pattern is matched on the dependency's intrinsic
  % tag, not on the local namespace alias.
  rewrite_constructor_tags(CodegenAst0, ConstructorTags, CodegenAst),
  generate(CodegenAst, JavaScript),
  compile_modules(Rest, Asts, PreludeModules, Interfaces1, Compiled).

% ---------------------------------------------------------------------------
% Import resolution: dependency interfaces -> seed environments + a plan that
% records, per `use`, the JS specifier and which names are runtime imports.
% ---------------------------------------------------------------------------

% In addition to the seed environments and the per-`use` import plan, this
% returns -- for whole-module (`use ./Math`) imports -- the namespace base
% names, the set of qualified value-member names (for access collapsing), and
% the [LocalConstructor - IntrinsicTag] pairs (for the codegen tag rewrite).
%
% `EffectivePreludes` is seeded FIRST (into `V0`/`T0`), before the file's own
% `Items` fold on top -- so an explicit `use` or a local declaration of the
% same name overrides a prelude entry exactly the way two ordinary imports
% would (see `resolve_import_items`/`build_type_environment`).  `PreludePlan`
% is a separate list of `namespace_plan/2` terms (one per prelude module) --
% they carry no corresponding `Items` node, so `rewrite_imports/4` turns them
% into codegen nodes directly rather than zipping them against `Items`.
resolve_imports(program_node(Items), Directory, Interfaces, EffectivePreludes,
                SeedValueEnvironment, SeedTypeEnvironment,
                PreludePlan, ImportPlan, NamespaceBases, NamespaceMembers, ConstructorTags) :-
  empty_assoc(V0),
  empty_assoc(T0),
  seed_preludes(EffectivePreludes, Directory, Interfaces, V0, T0, V1, T1,
               PreludePlan, PreludeBases, PreludeMembers, PreludeTags),
  resolve_import_items(Items, Directory, Interfaces, V1, T1, SeedValueEnvironment, SeedTypeEnvironment,
                       ImportPlan, ExplicitBases, ExplicitMembers, ExplicitTags),
  append(PreludeBases, ExplicitBases, NamespaceBases),
  append(PreludeMembers, ExplicitMembers, NamespaceMembers),
  append(PreludeTags, ExplicitTags, ConstructorTags).

% Seed the value/type environments from every effective prelude module's
% ALREADY-COMPILED interface (guaranteed present in `Interfaces`: the
% dependency graph compiles every prelude module before anything that can
% depend on it, implicitly or explicitly).  Namespace `[]` (see
% `namespace_import:qualify/3`) leaves each seeded name exactly as the
% prelude module exported it -- unprefixed for a flat name, already-dotted
% for a qualified companion-module name (`Optional.isSome`) -- and
% `prelude_bases/2` derives the namespace tokens (`Optional`) a caller's
% source can write for `collapse_namespace_access/4` to recognise, since
% there is no single `Namespace` token here the way there is for `use_all`.
seed_preludes([], _Directory, _Interfaces, V, T, V, T, [], [], [], []).
seed_preludes([PreludeModule | Rest], Directory, Interfaces, V0, T0, V, T,
             [namespace_plan(JsSpecifier, Renames) | Plans], Bases, Members, Tags) :-
  ( get_assoc(PreludeModule, Interfaces, Interface) ->
      true
  ; throw(analysis_error(missing_module(PreludeModule)))
  ),
  seed_namespace([], Interface, V0, T0, V1, T1, Renames, MemberNames, ModuleTags),
  prelude_bases(MemberNames, ModuleBases),
  relative_specifier(Directory, PreludeModule, JsSpecifier),
  seed_preludes(Rest, Directory, Interfaces, V1, T1, V, T, Plans, Bases1, Members1, Tags1),
  append(ModuleBases, Bases1, Bases),
  append(MemberNames, Members1, Members),
  append(ModuleTags, Tags1, Tags).

resolve_import_items([], _Directory, _Interfaces, V, T, V, T, [], [], [], []).
resolve_import_items([use_node(Path, Names, _) | Rest], Directory, Interfaces, V0, T0, V, T,
                     [import_plan(JsSpecifier, RuntimeNames) | Plans], Bases, Members, Tags) :- !,
  resolve_source_path(Directory, Path, Dependency),
  ( get_assoc(Dependency, Interfaces, Interface) ->
      true
  ; throw(analysis_error(missing_module(Dependency)))
  ),
  import_names(Names, Path, Interface, V0, T0, V1, T1, RuntimeNames),
  append(Path, ".js", JsSpecifier),
  resolve_import_items(Rest, Directory, Interfaces, V1, T1, V, T, Plans, Bases, Members, Tags).
resolve_import_items([use_all_node(Path, _) | Rest], Directory, Interfaces, V0, T0, V, T,
                     [namespace_plan(JsSpecifier, Renames) | Plans],
                     [Namespace | Bases], Members, Tags) :- !,
  resolve_source_path(Directory, Path, Dependency),
  ( get_assoc(Dependency, Interfaces, Interface) ->
      true
  ; throw(analysis_error(missing_module(Dependency)))
  ),
  namespace_of(Path, Namespace),
  seed_namespace(Namespace, Interface, V0, T0, V1, T1, Renames, MemberNames, NamespaceTags),
  append(Path, ".js", JsSpecifier),
  resolve_import_items(Rest, Directory, Interfaces, V1, T1, V, T, Plans, Bases, Members1, Tags1),
  append(MemberNames, Members1, Members),
  append(NamespaceTags, Tags1, Tags).
resolve_import_items([_Other | Rest], Directory, Interfaces, V0, T0, V, T, Plans, Bases, Members, Tags) :-
  resolve_import_items(Rest, Directory, Interfaces, V0, T0, V, T, Plans, Bases, Members, Tags).

import_names([], _Path, _Interface, V, T, V, T, []).
import_names([Name | Names], Path, Interface, V0, T0, V, T, RuntimeNames) :-
  Interface = module_interface(ValueEntries, TypeEntries),
  ( memberchk(Name - _, ValueEntries) -> IsValue = true ; IsValue = false ),
  ( memberchk(Name - _, TypeEntries) -> IsType = true ; IsType = false ),
  ( memberchk(constructor_key(Name) - _, TypeEntries) -> IsConstructor = true ; IsConstructor = false ),
  ( ( IsValue == true ; IsType == true ; IsConstructor == true ) ->
      true
  ; throw(analysis_error(unknown_import(Path, Name)))
  ),
  ( IsValue == true ->
      member(Name - ValueEntry, ValueEntries),
      put_assoc(Name, V0, ValueEntry, V1)
  ; V1 = V0
  ),
  ( IsType == true ->
      member(Name - TypeEntry, TypeEntries),
      put_assoc(Name, T0, TypeEntry, Ta)
  ; Ta = T0
  ),
  ( IsConstructor == true ->
      member(constructor_key(Name) - ConstructorEntry, TypeEntries),
      put_assoc(constructor_key(Name), Ta, ConstructorEntry, T1)
  ; T1 = Ta
  ),
  import_names(Names, Path, Interface, V1, T1, V, T, RestRuntime),
  ( IsValue == true ->
      RuntimeNames = [Name | RestRuntime]
  ; RuntimeNames = RestRuntime
  ).

% Replace each `use` with an `import_node` carrying the JS specifier and only
% the runtime (value / constructor) names; an import of types only carries no
% runtime names and is dropped entirely.  `PreludePlan` entries have no
% corresponding `Items` node (see `resolve_imports/11`), so they are turned
% into codegen nodes directly and PREPENDED, rather than zipped against
% `Items` the way the file's own explicit `use`s are.
rewrite_imports(program_node(Items), PreludePlan, ImportPlan, program_node(NewItems)) :-
  prelude_import_nodes(PreludePlan, PreludeNodes),
  rewrite_import_items(Items, ImportPlan, ExplicitNodes),
  append(PreludeNodes, ExplicitNodes, NewItems).

prelude_import_nodes([], []).
% An empty rename set (the prelude module exports no runtime values) is
% dropped entirely -- same rule as an explicit whole-module import below.
prelude_import_nodes([namespace_plan(_JsSpecifier, []) | Rest], Nodes) :- !,
  prelude_import_nodes(Rest, Nodes).
prelude_import_nodes([namespace_plan(JsSpecifier, Renames) | Rest], [namespace_import_node(JsSpecifier, Renames) | Nodes]) :-
  prelude_import_nodes(Rest, Nodes).

rewrite_import_items([], [], []).
rewrite_import_items([use_node(_, _, _) | Rest], [import_plan(JsSpecifier, RuntimeNames) | Plans], NewItems) :- !,
  ( RuntimeNames == [] ->
      NewItems = NewRest
  ; NewItems = [import_node(JsSpecifier, RuntimeNames) | NewRest]
  ),
  rewrite_import_items(Rest, Plans, NewRest).
% A whole-module import becomes a renamed ES import; an empty rename set (the
% dependency exports no runtime values) is dropped entirely.
rewrite_import_items([use_all_node(_, _) | Rest], [namespace_plan(JsSpecifier, Renames) | Plans], NewItems) :- !,
  ( Renames == [] ->
      NewItems = NewRest
  ; NewItems = [namespace_import_node(JsSpecifier, Renames) | NewRest]
  ),
  rewrite_import_items(Rest, Plans, NewRest).
rewrite_import_items([Item | Rest], Plans, [Item | NewRest]) :-
  rewrite_import_items(Rest, Plans, NewRest).
