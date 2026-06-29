:- module(module_loader, [compile_program/1]).

/*  module_loader.pl  --  Multi-file module loader and build driver.

    (Named `module_loader`, not `loader`: Scryer has a built-in `loader`
    module and shadowing it makes user modules fail to load.)

    Given an entry `.sl` file, this resolves the whole import graph, type-checks
    every module in dependency order, and writes one `.js` file per module.

    Pipeline:

        entry.sl --read_module-->   parse, then `expand_modules` erases nested
                                     `module`s (so the graph/import scan sees a
                                     `use` lifted out of a module body)
                 --build_graph-->   modules in topological order (deps first),
                                     import cycles rejected
                 --per module-->    resolve imports against already-compiled
                                     dependency interfaces, seed the analyser,
                                     collapse `namespace.member` accesses,
                                     `analyse_module`, rewrite `use`/`use_all`
                                     nodes to `import_node`/`namespace_import_node`,
                                     rewrite imported constructor patterns to
                                     their intrinsic tags, generate JavaScript,
                                     write `<module>.js`

    A MODULE is identified by its normalised absolute-ish source path (a
    character list).  `use ./math:(..)` in a file `Dir/a.sl` refers to the
    module `Dir/math.sl`; the emitted JavaScript imports from `"./math.js"`
    (the relative specifier the programmer wrote, with the extension swapped).

    A NAMED import (`use ./math:(a b)`) resolves each listed name across all
    three namespaces from the dependency's exported interface: a value seeds the
    value environment (and is a runtime import), a type seeds the type
    environment, a constructor seeds both.  A name absent from the interface is
    an `unknown_import` error.  A WHOLE-MODULE import (`use ./math`) seeds EVERY
    public entry under a `math.`-qualified local name -- see `namespace_import`.
*/

:- use_module(library(pio)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(assoc)).
:- use_module('syntax/lower', [parse_source/2]).
:- use_module(module_paths, [
  read_source_chars/2,
  normalise_path/2,
  module_directory/2,
  resolve_source_path/3,
  source_to_js_path/2
]).
:- use_module('transformation/module', [expand_modules/2]).
:- use_module('transformation/macro_program', [process_macros/3]).
:- use_module(namespace_import, [
  namespace_of/2,
  seed_namespace/9,
  collapse_namespace_access/4,
  rewrite_constructor_tags/3
]).
:- use_module(analyser, [analyse_module/5]).
:- use_module(generator, [generate/2]).

%% compile_program(+EntryPath).
%
% Compiles the module graph rooted at `EntryPath` (a `.sl` source path as a
% character list), writing a `.js` file beside each module.
compile_program(EntryPath) :-
  once((
    normalise_path(EntryPath, Entry),
    empty_assoc(Asts0),
    build_graph(Entry, [], Asts0, [], ParsedAsts, OrderReversed),
    reverse(OrderReversed, Order),
    % Reader macros are a WHOLE-PROGRAM compile-time layer: collect every
    % module's macros into one table, type-check them together (so a macro may
    % call one imported from another file), then expand each module against that
    % table.  This runs after the whole graph is parsed and before per-module
    % compilation, so cross-file `@name` uses resolve.
    process_macros(Order, ParsedAsts, Asts),
    empty_assoc(Interfaces0),
    compile_modules(Order, Asts, Interfaces0)
  )).


% ---------------------------------------------------------------------------
% Dependency graph (depth-first, post-order => dependencies first)
% ---------------------------------------------------------------------------

% build_graph(+Module, +InProgress, +AstsIn, +OrderIn, -AstsOut, -OrderOut).
% `InProgress` is the chain of ancestors currently being visited (for cycle
% detection); `Asts` memoises each module's parsed AST (and marks it done);
% `Order` accumulates modules with each placed before its dependencies, so the
% caller reverses it to get dependencies-first order.
build_graph(Module, _InProgress, AstsIn, OrderIn, AstsOut, OrderOut) :-
  get_assoc(Module, AstsIn, _), !,           % already compiled into the graph
  AstsOut = AstsIn,
  OrderOut = OrderIn.
build_graph(Module, InProgress, AstsIn, OrderIn, AstsOut, OrderOut) :-
  read_module(Module, Ast),
  module_dependencies(Ast, Module, Dependencies),
  build_graph_dependencies(Dependencies, [Module | InProgress], AstsIn, OrderIn, Asts1, Order1),
  put_assoc(Module, Asts1, Ast, AstsOut),
  OrderOut = [Module | Order1].

build_graph_dependencies([], _InProgress, Asts, Order, Asts, Order).
build_graph_dependencies([Dependency | Dependencies], InProgress, AstsIn, OrderIn, AstsOut, OrderOut) :-
  ( memberchk(Dependency, InProgress) ->
      throw(analysis_error(import_cycle(Dependency)))
  ; true
  ),
  build_graph(Dependency, InProgress, AstsIn, OrderIn, Asts1, Order1),
  build_graph_dependencies(Dependencies, InProgress, Asts1, Order1, AstsOut, OrderOut).

% Read and PARSE a module.  Macro expansion and nested-module erasure happen
% later (in `process_macros`), once the whole graph is known -- a `@name` use
% may resolve to a macro imported from another file, so expansion is a
% whole-program pass, not a per-file one.
read_module(Module, ParsedAst) :-
  ( read_source_chars(Module, Source) ->
      true
  ; throw(analysis_error(cannot_read_module(Module)))
  ),
  parse_source(Source, ParsedAst).

% Dependency scanning runs on the PARSED AST (nested modules not yet lifted), so
% it descends into `module` bodies to find their `use`s.  The builtin `Compiler`
% import is not a file dependency and is skipped.
module_dependencies(program_node(Items), Module, Dependencies) :-
  module_directory(Module, Directory),
  findall(Dependency,
          ( use_path(Items, Path),
            Path \== "Compiler",
            resolve_source_path(Directory, Path, Dependency) ),
          Dependencies).

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

compile_modules([], _Asts, _Interfaces).
compile_modules([Module | Rest], Asts, InterfacesIn) :-
  get_assoc(Module, Asts, Ast),
  module_directory(Module, Directory),
  resolve_imports(Ast, Directory, InterfacesIn, SeedValueEnvironment, SeedTypeEnvironment,
                  ImportPlan, NamespaceBases, NamespaceMembers, ConstructorTags),
  % Collapse `Namespace.member` value accesses to flat qualified identifiers
  % (using the imported interfaces' member sets) before anything reads the AST.
  collapse_namespace_access(Ast, NamespaceBases, NamespaceMembers, ResolvedAst),
  analyse_module(ResolvedAst, SeedValueEnvironment, SeedTypeEnvironment, _Result, Interface),
  put_assoc(Module, InterfacesIn, Interface, Interfaces1),
  rewrite_imports(ResolvedAst, ImportPlan, CodegenAst0),
  % An imported constructor's pattern is matched on the dependency's intrinsic
  % tag, not on the local namespace alias.
  rewrite_constructor_tags(CodegenAst0, ConstructorTags, CodegenAst),
  generate(CodegenAst, JavaScript),
  source_to_js_path(Module, JsPath),
  phrase_to_file(JavaScript, JsPath),
  compile_modules(Rest, Asts, Interfaces1).

% ---------------------------------------------------------------------------
% Import resolution: dependency interfaces -> seed environments + a plan that
% records, per `use`, the JS specifier and which names are runtime imports.
% ---------------------------------------------------------------------------

% In addition to the seed environments and the per-`use` import plan, this
% returns -- for whole-module (`use ./Math`) imports -- the namespace base
% names, the set of qualified value-member names (for access collapsing), and
% the [LocalConstructor - IntrinsicTag] pairs (for the codegen tag rewrite).
resolve_imports(program_node(Items), Directory, Interfaces, SeedValueEnvironment, SeedTypeEnvironment,
                ImportPlan, NamespaceBases, NamespaceMembers, ConstructorTags) :-
  empty_assoc(V0),
  empty_assoc(T0),
  resolve_import_items(Items, Directory, Interfaces, V0, T0, SeedValueEnvironment, SeedTypeEnvironment,
                       ImportPlan, NamespaceBases, NamespaceMembers, ConstructorTags).

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
% runtime names and is dropped entirely.
rewrite_imports(program_node(Items), ImportPlan, program_node(NewItems)) :-
  rewrite_import_items(Items, ImportPlan, NewItems).

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

