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
:- use_module(parser, [parse/2]).
:- use_module('transformation/module', [expand_modules/2]).
:- use_module('transformation/macro', [
  program_macros/2,
  program_compiler_imports/2,
  macro_table/2,
  check_macro_set/2,
  require_parse_item_import/2,
  macro_key_name/3,
  resolve_macro_body/3,
  resolve_uses/3,
  expand_program_with_table/3
]).
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
% Whole-program reader-macro processing
% ---------------------------------------------------------------------------

% Macro names are MODULE-SCOPED, so two files may reuse one.  Each macro gets a
% unique key (`Name#ModuleIndex`); a per-module RESOLUTION map sends each name as
% written in that module (bare, or `namespace.name` from a whole-module import)
% to the key it denotes.  We then: rewrite every macro body to keys (so the
% global key table is self-contained), type-check all macros together, and
% expand each module by resolving its `@name` uses to keys and interpreting.
process_macros(Order, ParsedAsts, ExpandedAsts) :-
  enforce_compiler_imports(Order, ParsedAsts),
  module_indices(Order, Indices),
  public_macros(Order, ParsedAsts, PublicMacros),
  build_macros(Order, ParsedAsts, Indices, PublicMacros, RootResolutions, KeyedDefinitions),
  gather_compiler_imports(Order, ParsedAsts, AllCompilerImports),
  macro_table(KeyedDefinitions, Table),
  check_macro_set(KeyedDefinitions, AllCompilerImports),
  expand_with_macros(Order, ParsedAsts, RootResolutions, PublicMacros, Table, ExpandedAsts).

% Per file: build its ROOT resolution (every macro by its qualified name, plus
% imported macros) -- used to resolve `@name` invocations -- and its keyed macro
% definitions (each body rewritten to keys using the macro's own module scope).
build_macros([], _Asts, _Indices, _PublicMacros, Empty, []) :- empty_assoc(Empty).
build_macros([File | Rest], Asts, Indices, PublicMacros, RootResolutions, KeyedDefinitions) :-
  get_assoc(File, Asts, program_node(Items)),
  get_assoc(File, Indices, FileIndex),
  module_directory(File, Directory),
  root_resolution(Items, FileIndex, Directory, Indices, PublicMacros, RootResolution),
  empty_assoc(EmptyBare),
  keyed_walk(Items, FileIndex, [], EmptyBare, RootResolution, Definitions),
  build_macros(Rest, Asts, Indices, PublicMacros, RootResolutions0, RestDefinitions),
  put_assoc(File, RootResolutions0, RootResolution, RootResolutions),
  append(Definitions, RestDefinitions, KeyedDefinitions).

% The whole-program type check pools every module's `Compiler` imports, so it
% cannot tell which module imported `parseItem`.  Enforce that PER MODULE here:
% a module whose macros use `parseItem` must itself import it.
enforce_compiler_imports([], _ParsedAsts).
enforce_compiler_imports([Module | Rest], ParsedAsts) :-
  get_assoc(Module, ParsedAsts, program_node(Items)),
  all_file_macros(Items, MacroDefinitions),
  program_compiler_imports(program_node(Items), CompilerImportNames),
  require_parse_item_import(MacroDefinitions, CompilerImportNames),
  enforce_compiler_imports(Rest, ParsedAsts).

% Every macro defined in a file, at the top level or nested in a `module`.
all_file_macros([], []).
all_file_macros([Item | Rest], MacroDefinitions) :-
  ( local_macro(Item, Name, Parameters, Body, Span) ->
      ItemMacros = [macro_definition_node(Name, Parameters, Body, Span)]
  ; module_body(Item, Body) ->
      all_file_macros(Body, ItemMacros)
  ; ItemMacros = []
  ),
  all_file_macros(Rest, RestMacros),
  append(ItemMacros, RestMacros, MacroDefinitions).

% --- module index (for unique keys) ---------------------------------------
module_indices(Order, Indices) :-
  empty_assoc(Empty),
  module_indices(Order, 0, Empty, Indices).
module_indices([], _Index, Indices, Indices).
module_indices([Module | Rest], Index, AccumulatorIn, Indices) :-
  put_assoc(Module, AccumulatorIn, Index, Accumulator1),
  Index1 is Index + 1,
  module_indices(Rest, Index1, Accumulator1, Indices).

% --- each module's exported (public) macro names ---------------------------
public_macros(Order, Asts, PublicMacros) :-
  empty_assoc(Empty),
  public_macros(Order, Asts, Empty, PublicMacros).
public_macros([], _Asts, PublicMacros, PublicMacros).
public_macros([Module | Rest], Asts, AccumulatorIn, PublicMacros) :-
  get_assoc(Module, Asts, program_node(Items)),
  public_macro_names(Items, Names),
  put_assoc(Module, AccumulatorIn, Names, Accumulator1),
  public_macros(Rest, Asts, Accumulator1, PublicMacros).

public_macro_names([], []).
public_macro_names([public_node(macro_definition_node(Name, _, _, _), _) | Rest], [Name | Names]) :- !,
  public_macro_names(Rest, Names).
public_macro_names([_Other | Rest], Names) :-
  public_macro_names(Rest, Names).

% --- per-file root resolution (qualified names + imported macros) ----------
% A macro's QUALIFIED name is its dotted module path + short name: a top-level
% `inc` is `inc`; an `inc` in `module Math` is `Math.inc`.  `@Math.inc` reaches
% it from anywhere in the file; bare `@inc` reaches a TOP-LEVEL macro.  (Inside a
% module, a sibling/self macro is referenced by bare name in a macro BODY -- see
% keyed_walk -- while an `@`-invocation uses the qualified name.)
root_resolution(Items, FileIndex, Directory, Indices, PublicMacros, RootResolution) :-
  empty_assoc(Empty),
  qualified_map(Items, FileIndex, [], Empty, QualifiedMap),
  add_imported_macros(Items, Directory, Indices, PublicMacros, QualifiedMap, RootResolution).

% Map every macro (recursively, through nested modules) by its qualified name.
qualified_map([], _FileIndex, _Prefix, Map, Map).
qualified_map([Item | Rest], FileIndex, Prefix, MapIn, MapOut) :-
  ( local_macro(Item, Name, _, _, _) ->
      extend_prefix(Prefix, Name, QualifiedName),
      macro_key_name(FileIndex, QualifiedName, Key),
      ( get_assoc(QualifiedName, MapIn, _) ->
          throw(analysis_error(duplicate_macro(QualifiedName)))
      ; true
      ),
      put_assoc(QualifiedName, MapIn, Key, Map1)
  ; module_node_item(Item, ModuleName, Body) ->
      extend_prefix(Prefix, ModuleName, ChildPrefix),
      qualified_map(Body, FileIndex, ChildPrefix, MapIn, Map1)
  ; Map1 = MapIn
  ),
  qualified_map(Rest, FileIndex, Prefix, Map1, MapOut).

% A macro's qualified name: its module path dotted onto its short name.  The
% result is rebuilt into ONE canonical representation (fresh cons cells), so it
% compares equal as an `assoc` key to the name the parser produces for an
% `@`-invocation (see `canonical_chars/2`); otherwise the lookup silently misses.
extend_prefix([], Name, Canonical) :- !,
  canonical_chars(Name, Canonical).
extend_prefix(Prefix, Name, Canonical) :-
  append(Prefix, ['.' | Name], Raw),
  canonical_chars(Raw, Canonical).

canonical_chars([], []).
canonical_chars([Character | Characters], [Character | Rest]) :-
  canonical_chars(Characters, Rest).

% A (possibly `public`) nested module's name and body.
module_node_item(module_node(Name, Body, _Span), Name, Body).
module_node_item(public_node(module_node(Name, Body, _Span), _), Name, Body).

% The body of a (possibly `public`) nested module (name not needed).
module_body(module_node(_Name, Body, _Span), Body).
module_body(public_node(module_node(_Name, Body, _Span), _), Body).

% --- keyed definitions, with scope-aware bodies ----------------------------
% Walk the module tree.  At each scope a macro BODY may reference, by bare name,
% any macro in the same module or an enclosing one (inner shadows outer), plus
% anything in the root resolution (top-level and imported macros).  Each body is
% rewritten to keys against that scope's resolution.
keyed_walk(Items, FileIndex, Prefix, InheritedBare, RootResolution, Definitions) :-
  level_bare(Items, FileIndex, Prefix, InheritedBare, ScopeBare),
  merge_into(RootResolution, ScopeBare, BodyResolution),
  walk_keyed_items(Items, FileIndex, Prefix, ScopeBare, RootResolution, BodyResolution, Definitions).

% Bare names bound at this scope: inherited (enclosing modules) plus this level's
% own macros, which override.
level_bare([], _FileIndex, _Prefix, Bare, Bare).
level_bare([Item | Rest], FileIndex, Prefix, BareIn, BareOut) :-
  ( local_macro(Item, Name, _, _, _) ->
      extend_prefix(Prefix, Name, QualifiedName),
      macro_key_name(FileIndex, QualifiedName, Key),
      put_assoc(Name, BareIn, Key, Bare1)
  ; Bare1 = BareIn
  ),
  level_bare(Rest, FileIndex, Prefix, Bare1, BareOut).

walk_keyed_items([], _FileIndex, _Prefix, _ScopeBare, _RootResolution, _BodyResolution, []).
walk_keyed_items([Item | Rest], FileIndex, Prefix, ScopeBare, RootResolution, BodyResolution, Definitions) :-
  ( local_macro(Item, Name, Parameters, Body, Span) ->
      extend_prefix(Prefix, Name, QualifiedName),
      macro_key_name(FileIndex, QualifiedName, Key),
      resolve_macro_body(Body, BodyResolution, KeyedBody),
      ItemDefinitions = [macro_definition_node(Key, Parameters, KeyedBody, Span)]
  ; module_node_item(Item, ModuleName, ModuleBody) ->
      extend_prefix(Prefix, ModuleName, ChildPrefix),
      keyed_walk(ModuleBody, FileIndex, ChildPrefix, ScopeBare, RootResolution, ItemDefinitions)
  ; ItemDefinitions = []
  ),
  walk_keyed_items(Rest, FileIndex, Prefix, ScopeBare, RootResolution, BodyResolution, RestDefinitions),
  append(ItemDefinitions, RestDefinitions, Definitions).

% `Result` is `Base` with every entry of `Overlay` put on top (Overlay wins).
merge_into(Base, Overlay, Result) :-
  assoc_to_list(Overlay, Pairs),
  put_pairs(Pairs, Base, Result).
put_pairs([], Assoc, Assoc).
put_pairs([Key-Value | Rest], AssocIn, AssocOut) :-
  put_assoc(Key, AssocIn, Value, Assoc1),
  put_pairs(Rest, Assoc1, AssocOut).

add_imported_macros([], _Directory, _Indices, _PublicMacros, Resolution, Resolution).
add_imported_macros([use_node(Path, Names, _) | Rest], Directory, Indices, PublicMacros, ResolutionIn, ResolutionOut) :-
  Path \== "Compiler", !,
  dependency_macros(Directory, Path, Indices, PublicMacros, DependencyIndex, DependencyPublics),
  add_named_macro_imports(Names, DependencyIndex, DependencyPublics, ResolutionIn, Resolution1),
  add_imported_macros(Rest, Directory, Indices, PublicMacros, Resolution1, ResolutionOut).
add_imported_macros([use_all_node(Path, _) | Rest], Directory, Indices, PublicMacros, ResolutionIn, ResolutionOut) :-
  !,
  dependency_macros(Directory, Path, Indices, PublicMacros, DependencyIndex, DependencyPublics),
  namespace_of(Path, Namespace),
  add_whole_macro_imports(DependencyPublics, Namespace, DependencyIndex, ResolutionIn, Resolution1),
  add_imported_macros(Rest, Directory, Indices, PublicMacros, Resolution1, ResolutionOut).
add_imported_macros([_Other | Rest], Directory, Indices, PublicMacros, ResolutionIn, ResolutionOut) :-
  add_imported_macros(Rest, Directory, Indices, PublicMacros, ResolutionIn, ResolutionOut).

dependency_macros(Directory, Path, Indices, PublicMacros, DependencyIndex, DependencyPublics) :-
  resolve_source_path(Directory, Path, DependencyPath),
  ( get_assoc(DependencyPath, Indices, DependencyIndex),
    get_assoc(DependencyPath, PublicMacros, DependencyPublics)
  -> true
  ;  DependencyIndex = 0, DependencyPublics = []     % not a known module (no macros)
  ).

add_named_macro_imports([], _Index, _Publics, Resolution, Resolution).
add_named_macro_imports([Name | Names], Index, Publics, ResolutionIn, ResolutionOut) :-
  ( memberchk(Name, Publics) ->
      macro_key_name(Index, Name, Key),
      put_assoc(Name, ResolutionIn, Key, Resolution1)
  ; Resolution1 = ResolutionIn
  ),
  add_named_macro_imports(Names, Index, Publics, Resolution1, ResolutionOut).

add_whole_macro_imports([], _Namespace, _Index, Resolution, Resolution).
add_whole_macro_imports([Name | Names], Namespace, Index, ResolutionIn, ResolutionOut) :-
  qualified_macro_name(Namespace, Name, QualifiedName),
  macro_key_name(Index, Name, Key),
  put_assoc(QualifiedName, ResolutionIn, Key, Resolution1),
  add_whole_macro_imports(Names, Namespace, Index, Resolution1, ResolutionOut).

qualified_macro_name(Namespace, Name, Canonical) :-
  append(Namespace, ['.' | Name], Raw),
  canonical_chars(Raw, Canonical).

local_macro(macro_definition_node(Name, Parameters, Body, Span), Name, Parameters, Body, Span).
local_macro(public_node(macro_definition_node(Name, Parameters, Body, Span), _), Name, Parameters, Body, Span).

gather_compiler_imports([], _Asts, []).
gather_compiler_imports([Module | Rest], Asts, All) :-
  get_assoc(Module, Asts, Ast),
  program_compiler_imports(Ast, Imports),
  gather_compiler_imports(Rest, Asts, RestImports),
  append(Imports, RestImports, All).

% --- per-module expansion --------------------------------------------------
expand_with_macros([], Asts, _Resolutions, _PublicMacros, _Table, Asts).
expand_with_macros([Module | Rest], AstsIn, Resolutions, PublicMacros, Table, AstsOut) :-
  get_assoc(Module, AstsIn, ParsedAst),
  get_assoc(Module, Resolutions, Resolution),
  module_directory(Module, Directory),
  % `@name` uses -> keys; drop macro definitions, the Compiler import, and macro
  % names from `use` lists; interpret invocations; then erase nested modules.
  resolve_uses(ParsedAst, Resolution, program_node(ResolvedItems)),
  strip_macro_items(ResolvedItems, Directory, PublicMacros, Kept),
  expand_program_with_table(program_node(Kept), Table, MacroExpandedAst),
  expand_modules(MacroExpandedAst, ModuleExpandedAst),
  put_assoc(Module, AstsIn, ModuleExpandedAst, Asts1),
  expand_with_macros(Rest, Asts1, Resolutions, PublicMacros, Table, AstsOut).

strip_macro_items([], _Directory, _PublicMacros, []).
strip_macro_items([use_node(Path, _Names, _Span) | Rest], Directory, PublicMacros, Kept) :-
  Path == "Compiler", !,
  strip_macro_items(Rest, Directory, PublicMacros, Kept).
strip_macro_items([use_node(Path, Names, Span) | Rest], Directory, PublicMacros, Kept) :- !,
  resolve_source_path(Directory, Path, DependencyPath),
  ( get_assoc(DependencyPath, PublicMacros, DependencyPublics) -> true ; DependencyPublics = [] ),
  exclude_public_macros(Names, DependencyPublics, Remaining),
  ( Remaining == [] ->
      Kept = Kept1                          % imported only macros: drop the `use`
  ; Kept = [use_node(Path, Remaining, Span) | Kept1]
  ),
  strip_macro_items(Rest, Directory, PublicMacros, Kept1).
strip_macro_items([Item | Rest], Directory, PublicMacros, Kept) :-
  ( local_macro(Item, _, _, _, _) ->
      Kept = Kept1                          % drop a macro definition
  ; strip_nested_module(Item, Directory, PublicMacros, Item1) ->
      Kept = [Item1 | Kept1]                % recurse: strip macros from its body
  ; Kept = [Item | Kept1]
  ),
  strip_macro_items(Rest, Directory, PublicMacros, Kept1).

% Rebuild a (possibly `public`) nested module with macro definitions stripped
% from its body, so the module expander never sees a macro node.
strip_nested_module(module_node(Name, Body, Span), Directory, PublicMacros, module_node(Name, Body1, Span)) :-
  strip_macro_items(Body, Directory, PublicMacros, Body1).
strip_nested_module(public_node(module_node(Name, Body, Span), PSpan), Directory, PublicMacros,
                    public_node(module_node(Name, Body1, Span), PSpan)) :-
  strip_macro_items(Body, Directory, PublicMacros, Body1).

exclude_public_macros([], _Publics, []).
exclude_public_macros([Name | Names], Publics, Remaining) :-
  ( memberchk(Name, Publics) ->
      Remaining = Remaining1
  ; Remaining = [Name | Remaining1]
  ),
  exclude_public_macros(Names, Publics, Remaining1).

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
  ( catch(phrase_from_file(all_chars(RawSource), Module), _, fail) ->
      true
  ; throw(analysis_error(cannot_read_module(Module)))
  ),
  % `phrase_from_file` yields a partial-string-backed list; force a plain cons
  % list of character atoms so that names built later by appending (qualified
  % module names) share one representation with names read by the parser.
  % Otherwise equal-looking names can differ as `assoc` keys (their `compare/3`
  % order is representation-sensitive) and qualified lookups silently miss.
  force_char_list(RawSource, Source),
  parse(Source, ParsedAst).

force_char_list([], []).
force_char_list([Character | Characters], [Character | Forced]) :-
  force_char_list(Characters, Forced).

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

% ---------------------------------------------------------------------------
% Paths
% ---------------------------------------------------------------------------

% The dependency's source path: the importer's directory joined with the
% relative `use` path, with a `.sl` extension, normalised.
resolve_source_path(Directory, RelativePath, SourcePath) :-
  append(Directory, "/", DirectorySlash),
  append(DirectorySlash, RelativePath, Joined),
  append(Joined, ".sl", WithExtension),
  normalise_path(WithExtension, SourcePath).

source_to_js_path(SourcePath, JsPath) :-
  ( append(Prefix, ".sl", SourcePath) ->
      append(Prefix, ".js", JsPath)
  ; JsPath = SourcePath
  ).

% Everything up to (not including) the last `/`; `.` when there is none.
module_directory(Path, Directory) :-
  reverse(Path, Reversed),
  ( append(_FileReversed, ['/' | DirectoryReversed], Reversed) ->
      reverse(DirectoryReversed, Directory)
  ; Directory = ['.']
  ).

% Resolve `.` and `..` segments.
normalise_path(Path, Normalised) :-
  split_on_slash(Path, Segments),
  resolve_segments(Segments, [], ResolvedReversed),
  reverse(ResolvedReversed, Resolved),
  join_on_slash(Resolved, Joined),
  % Force a canonical cons-list representation: append/2 above can leave a
  % partial-string tail, and `library(assoc)` keys compare partial strings and
  % plain cons lists as DIFFERENT.  Mixing the two across path keys corrupts the
  % AVL once it holds 3+ modules (a present key then silently misses).
  canonical_chars(Joined, Normalised).

split_on_slash(Chars, [Segment | Segments]) :-
  append(Segment, ['/' | Rest], Chars), !,
  split_on_slash(Rest, Segments).
split_on_slash(Chars, [Chars]).

resolve_segments([], Accumulator, Accumulator).
resolve_segments([Segment | Rest], Accumulator, Out) :-
  ( Segment = ['.'] ->
      Accumulator1 = Accumulator
  ; Segment = ['.', '.'] ->
      ( Accumulator = [Top | AccumulatorRest], Top \= ['.', '.'], Top \= [] ->
          Accumulator1 = AccumulatorRest
      ; Accumulator1 = [Segment | Accumulator]
      )
  ; Accumulator1 = [Segment | Accumulator]
  ),
  resolve_segments(Rest, Accumulator1, Out).

join_on_slash([], []).
join_on_slash([Segment], Segment) :- !.
join_on_slash([Segment | Segments], Joined) :-
  join_on_slash(Segments, Rest),
  append(Segment, ['/' | Rest], Joined).

% Match (or emit) an entire list of characters verbatim.
all_chars([]) --> [].
all_chars([Character | Characters]) -->
  [Character],
  all_chars(Characters).
