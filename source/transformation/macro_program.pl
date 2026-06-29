:- module(macro_program, [process_macros/3]).

/*  transformation/macro_program.pl  --  Whole-program reader-macro processing.

    Macros are a WHOLE-PROGRAM compile-time layer: a macro in one file may call
    one imported from another, and a macro name is module-scoped, so resolving
    `@name` invocations to the macro they denote needs the whole import graph.
    This module turns a set of parsed modules (deps-first `Order` + a path->AST
    `assoc`) into the same set with every `@name(..)` invocation expanded and
    every macro definition / `Compiler` import erased.

    It is shared by BOTH pipelines:
      * the batch build driver (`module_loader.pl`), over the full program graph;
      * the incremental engine (`syntax/queries.pl`), over a single file's
        dependency closure -- so a file using macros type-checks in the editor.
    Keeping it out of `module_loader` keeps the code generator (which the loader
    pulls in, but the editor front-end does not need) off the engine's path.

    The expansion is index-stable: macro KEYS (`Name#Index`) are internal and
    never reach codegen, so numbering a single file's closure independently of
    the whole program yields the SAME expanded AST.
*/

% This module compares `use` paths against the string literal "Compiler"; read
% string literals as chars (like the AST names) regardless of file load order.
:- set_prolog_flag(double_quotes, chars).

:- use_module(library(assoc)).
:- use_module(library(lists)).
:- use_module('../module_paths', [
  canonical_chars/2,
  resolve_source_path/3,
  module_directory/2
]).
:- use_module(macro, [
  program_compiler_imports/2,
  require_parse_item_import/2,
  macro_table/2,
  check_macro_set/2,
  macro_key_name/3,
  resolve_macro_body/3,
  resolve_uses/3,
  expand_program_with_table/3
]).
:- use_module('../namespace_import', [namespace_of/2]).
:- use_module('module', [expand_modules/2]).

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
% `@`-invocation (see `module_paths:canonical_chars/2`); otherwise the lookup
% silently misses.
extend_prefix([], Name, Canonical) :- !,
  canonical_chars(Name, Canonical).
extend_prefix(Prefix, Name, Canonical) :-
  append(Prefix, ['.' | Name], Raw),
  canonical_chars(Raw, Canonical).

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
