:- module(analyser, [analyse/2, analyse_module/5, analyse_accumulating/6]).

/*  analyser.pl  --  Type checker entry point.

    Given a program AST (as produced by `source/parser.pl`) this computes
    its principal type, following the level-based Hindley-Milner inference
    of Fan, Xu & Xie, "Practical Type Inference with Levels" (PLDI'25),
    with let-generalisation / instantiation as in Heeren, Hage &
    Swierstra, "Generalizing Hindley-Milner Type Inference Algorithms".

    Pipeline:

        AST  --build_type_environment-->  declared type constructors
             --infer_program-->           (LastType, FinalContext)
             --fully_resolve-->           principal type + final substitution

    The flow of a single check is:

      1. Start at typing level 0 with an empty environment and an empty
         algorithmic context (`types:empty_context/1`).
      2. `infer:infer_program/3` walks the AST.  Top-level definitions act
         as nested `let`s: each is typed one level deeper and then
         generalised over the unification variables that remained at that
         deeper level (the level trick that replaces the usual scan of the
         whole environment).  Lambdas introduce monomorphic parameters;
         applications, conditionals and operators drive unification, which
         lowers variable levels as needed to keep generalisation sound.
      3. The program's type is the type of its last expression, which we
         `zonk` (apply the final substitution to) so no solved variables
         remain.

    On a type error an `analysis_error(Reason)` exception is thrown by the
    unifier; `analyse/2` lets it propagate to the caller.
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).
:- use_module(analyser/types, [
  empty_context/1,
  fully_resolve/3,
  scheme_free_unification_variables/2,
  context_substitution/2
]).
:- use_module(analyser/type_environment, [
  build_type_environment/4,
  convert_annotation_type/6,
  seed_externals/7
]).
:- use_module(analyser/infer, [infer_program/6, infer_program_accumulating/7]).

% analyse(+AST, -Result).
%
% `Result` is `analysis_result(Type, Substitution)` where `Type` is the
% fully-resolved principal type of the program and `Substitution` is the
% solved part of the final algorithmic context as a list `Id = Type`.
%
% Before inference we collect and validate every `type` declaration into a
% `TypeEnvironment` (so annotations resolve to monotypes) and seed the term
% environment with every tagged-union constructor as a value.
analyse(AST, Result) :-
  empty_assoc(EmptyValueEnvironment),
  empty_assoc(EmptyTypeEnvironment),
  analyse_module(AST, EmptyValueEnvironment, EmptyTypeEnvironment, Result, _Exports).

% analyse_module(+AST, +SeedValueEnvironment, +SeedTypeEnvironment, -Result, -Exports).
%
% Type-checks one module.  `SeedValueEnvironment` / `SeedTypeEnvironment` are
% assocs pre-populated by the module loader with the entries this module
% imports (values, type names, and `constructor_key/1` constructor entries).
% `Result` is the usual `analysis_result(Type, Substitution)`.  `Exports` is
% `module_exports(ValueEntries, TypeEntries)`: the assoc-ready entries this
% module makes `public`, ready to seed an importing module.
%
% `public` wrappers are unwrapped and `use` / `use_all` declarations dropped
% before inference (the loader has already turned imports into seed entries);
% the set of exported names is remembered so the exports can be collected
% afterwards.  A nested `module` is NOT erased -- `infer.pl`'s own
% `infer_sequence_item` clause for `module_node` type-checks it directly,
% producing a genuine record value (see infer.pl's module documentation).
analyse_module(program_node(Items), SeedValueEnvironment, SeedTypeEnvironment,
               analysis_result(Type, Substitution),
               module_exports(ValueEntries, TypeEntries)) :-
  normalise_items(Items, CleanItems, PublicValueNames, PublicTypeDeclarations),
  CleanAST = program_node(CleanItems),
  build_type_environment(CleanAST, SeedTypeEnvironment, TypeEnvironment, ConstructorBindings),
  constructor_environment(ConstructorBindings, SeedValueEnvironment, ConstructorEnvironment),
  empty_context(Context0),
  % `external` declarations have no body to infer: their ascribed type is taken
  % on trust and seeded into the environment as a normal (generalised) scheme,
  % so the rest of the module sees them like any other top-level binding.
  seed_externals(CleanItems, TypeEnvironment, 0, ConstructorEnvironment, Context0, InitialEnvironment, Context1),
  infer_program(CleanAST, TypeEnvironment, InitialEnvironment, Context1,
                program_type(LastType, Context), FinalEnvironment),
  fully_resolve(LastType, Context, Type),
  context_substitution(Context, Substitution),
  collect_exports(PublicValueNames, PublicTypeDeclarations, FinalEnvironment, TypeEnvironment,
                  ValueEntries, TypeEntries).

% analyse_accumulating(+AST, +SeedValueEnv, +SeedTypeEnv, -Errors, -DefinitionTypes, -Exports).
%
% The SAME checker as `analyse_module/5` -- identical environment setup and the
% identical inference rules -- but it ACCUMULATES type errors instead of
% throwing on the first (via `infer:infer_program_accumulating/7`).  `Errors` is
% a list of `error_at(Span, Reason)`.  `DefinitionTypes` is `Name - ResolvedType`
% for each top-level definition (for editor hover).  `Exports` is this module's
% `module_exports(ValueEntries, TypeEntries)` -- exactly the shape
% `analyse_module/5` produces -- so the incremental engine can seed an importing
% file's environment from it (cross-file imports).  This is the single
% full-coverage checker the LSP / incremental engine uses; the batch compiler
% keeps `analyse/2` (which throws on the first error).
%
% Export collection here is BEST-EFFORT (unlike `collect_exports/6`, which
% throws): in an editor a module is often mid-edit, so a public name whose body
% failed to type is simply omitted from the exports rather than aborting the
% whole analysis.
analyse_accumulating(program_node(Items), SeedValueEnvironment, SeedTypeEnvironment, Errors, DefinitionTypes,
                     module_exports(ValueEntries, TypeEntries)) :-
  normalise_items(Items, CleanItems, PublicValueNames, PublicTypeDeclarations),
  CleanAST = program_node(CleanItems),
  build_type_environment(CleanAST, SeedTypeEnvironment, TypeEnvironment, ConstructorBindings),
  constructor_environment(ConstructorBindings, SeedValueEnvironment, ConstructorEnvironment),
  empty_context(Context0),
  seed_externals(CleanItems, TypeEnvironment, 0, ConstructorEnvironment, Context0, InitialEnvironment, Context1),
  infer_program_accumulating(CleanAST, TypeEnvironment, InitialEnvironment, Context1,
                             program_type(_LastType, Context), FinalEnvironment, Errors),
  definition_types(CleanItems, FinalEnvironment, Context, DefinitionTypes),
  collect_exports_best_effort(PublicValueNames, PublicTypeDeclarations, FinalEnvironment, TypeEnvironment,
                              ValueEntries, TypeEntries).

% Like `collect_exports/6`, but omits any name that is missing or ambiguous
% rather than throwing (see `analyse_accumulating/6`).
collect_exports_best_effort(ValueNames, TypeDeclarations, FinalEnvironment, TypeEnvironment,
                            ValueEntries, TypeEntries) :-
  export_values_best_effort(ValueNames, FinalEnvironment, ValueValueEntries),
  export_types_best_effort(TypeDeclarations, FinalEnvironment, TypeEnvironment, TypeValueEntries, TypeEntries),
  append(ValueValueEntries, TypeValueEntries, ValueEntries).

export_values_best_effort([], _Environment, []).
export_values_best_effort([Name | Names], Environment, Entries) :-
  ( get_assoc(Name, Environment, defined(Scheme)),
    scheme_free_unification_variables(Scheme, []) ->
      Entries = [Name - defined(Scheme) | Rest]
  ; Entries = Rest ),
  export_values_best_effort(Names, Environment, Rest).

export_types_best_effort([], _Environment, _TypeEnvironment, [], []).
export_types_best_effort([type_declaration_node(Name, _Parameters, Opacity, Body, _) | Declarations],
                         Environment, TypeEnvironment, ValueEntries, TypeEntries) :-
  ( get_assoc(Name, TypeEnvironment, Info) ->
      ( Opacity == opaque ->
          % An abstract type crosses the file boundary as its name alone.
          ConstructorValueEntries = [], ConstructorTypeEntries = []
      ; export_constructors_best_effort(Body, Environment, TypeEnvironment, ConstructorValueEntries, ConstructorTypeEntries)
      ),
      HeadTypeEntries = [Name - Info | ConstructorTypeEntries]
  ; ConstructorValueEntries = [], HeadTypeEntries = [] ),
  export_types_best_effort(Declarations, Environment, TypeEnvironment, RestValueEntries, RestTypeEntries),
  append(ConstructorValueEntries, RestValueEntries, ValueEntries),
  append(HeadTypeEntries, RestTypeEntries, TypeEntries).

export_constructors_best_effort(variant_body(Constructors), Environment, TypeEnvironment,
                                ValueEntries, TypeEntries) :- !,
  export_constructor_list_best_effort(Constructors, Environment, TypeEnvironment, ValueEntries, TypeEntries).
export_constructors_best_effort(_OtherBody, _Environment, _TypeEnvironment, [], []).

export_constructor_list_best_effort([], _Environment, _TypeEnvironment, [], []).
export_constructor_list_best_effort([constructor(CtorName, _Fields, _) | Rest], Environment, TypeEnvironment,
                                    ValueEntries, TypeEntries) :-
  ( get_assoc(CtorName, Environment, defined(CtorScheme)),
    get_assoc(constructor_key(CtorName), TypeEnvironment, CtorInfo) ->
      ValueEntries = [CtorName - defined(CtorScheme) | RestValueEntries],
      TypeEntries = [constructor_key(CtorName) - CtorInfo | RestTypeEntries]
  ; ValueEntries = RestValueEntries, TypeEntries = RestTypeEntries ),
  export_constructor_list_best_effort(Rest, Environment, TypeEnvironment, RestValueEntries, RestTypeEntries).

% Resolve each top-level definition's generalised scheme to a display monotype.
definition_types([], _Environment, _Context, []).
definition_types([definition_node(identifier_node(Name, _), _, _, _) | Rest], Environment, Context,
                 [Name - Resolved | DefinitionTypes]) :- !,
  ( get_assoc(Name, Environment, defined(type_scheme(QuantifiedIdentifiers, Body))) ->
      fully_resolve(Body, Context, ResolvedBody),
      ( QuantifiedIdentifiers = [] ->
          Resolved = ResolvedBody
      ; Resolved = forall_type(QuantifiedIdentifiers, ResolvedBody)
      )
  ; Resolved = unknown ),
  definition_types(Rest, Environment, Context, DefinitionTypes).
% An `external Name: Type = ...` (foreign JS import) has no VALUE to check
% against, but it is bound into `Environment` up front by `seed_externals/7`
% (called before inference, above) exactly like an ordinary top-level
% annotation would be -- so the SAME lookup that resolves a `definition_node`
% above already has its scheme sitting there waiting. Without this clause an
% external falls through to the catch-all below (which only exists to SKIP
% node kinds hover has nothing to say about) and hover on e.g. `panic` finds
% nothing, even though its declared type is right there in the source.
definition_types([external_node(Name, _Type, _Source, _Span) | Rest], Environment, Context,
                 [Name - Resolved | DefinitionTypes]) :- !,
  ( get_assoc(Name, Environment, defined(type_scheme(QuantifiedIdentifiers, Body))) ->
      fully_resolve(Body, Context, ResolvedBody),
      ( QuantifiedIdentifiers = [] ->
          Resolved = ResolvedBody
      ; Resolved = forall_type(QuantifiedIdentifiers, ResolvedBody)
      )
  ; Resolved = unknown ),
  definition_types(Rest, Environment, Context, DefinitionTypes).
% A `module Name<Params> = { ... }` binds `Name` to the module's own value
% type via `put_assoc/4` in `infer_sequence_item/9`'s `module_node` clause
% exactly like a `definition_node` does -- so the module's OWN hover entry
% (`Box` itself) needs nothing new, same lookup as above.
%
% Its MEMBERS (`wrap` inside `Box`) are different: they are type-checked in a
% private environment local to that same `infer_sequence_item` call (built by
% `infer_sequence` over the module's own items, then discarded once the
% module's row is built) -- never merged into `Environment`, so there is no
% `Name`-keyed scheme for e.g. `wrap` to look up directly here.
%
% But a TRANSPARENT module's resolved type already IS that row: one
% `record_field(_, label(MemberName), MemberType)` per public member (see
% `module_member_row/3`). So once the module's own type is resolved below,
% each member's type is just a field lookup away (`module_member_types/2`) --
% no need to reach back into that discarded private environment at all. An
% OPAQUE module's row is hidden BY DESIGN (its resolved type is a bare
% `type_constructor(Name, [])`, no fields) -- so its members simply get no
% entry here, the same graceful "no hover" as any other name this predicate
% cannot resolve, not a bug: opacity means there is nothing to show.
%
% Every member ends up in the SAME flat `Name - Type` list a top-level
% definition would, with no "Box." qualification -- deliberately, since that
% is the granularity hover already works at (`node_at` gives a bare
% identifier's text; see `lsp/lsp.pl`'s `definition_at/4`), so a USE site
% like `Box.wrap`'s `wrap` token resolves through the exact same lookup as
% the member's own definition site, for free. Trade-off inherited from that
% existing flat-by-name design, not introduced here: two distinct modules
% with a same-named member are ambiguous (the first match in the list wins) --
% no worse than any other shadowed name already is in this hover model.
definition_types([module_node(Name, _Parameters, _Opacity, _Ascription, _Items, _Span) | Rest],
                 Environment, Context, AllDefinitionTypes) :- !,
  ( get_assoc(Name, Environment, defined(type_scheme(QuantifiedIdentifiers, Body))) ->
      fully_resolve(Body, Context, ResolvedBody),
      ( QuantifiedIdentifiers = [] ->
          Resolved = ResolvedBody
      ; Resolved = forall_type(QuantifiedIdentifiers, ResolvedBody)
      )
  ; Resolved = unknown ),
  module_member_types(Resolved, MemberDefinitionTypes),
  definition_types(Rest, Environment, Context, RestDefinitionTypes),
  append([Name - Resolved | MemberDefinitionTypes], RestDefinitionTypes, AllDefinitionTypes).
definition_types([_Other | Rest], Environment, Context, DefinitionTypes) :-
  definition_types(Rest, Environment, Context, DefinitionTypes).

% module_member_types(+ModuleResolvedType, -MemberDefinitionTypes): pull
% `MemberName - MemberType` out of a transparent module's own resolved row
% type. Anything else (an opaque module's synthetic `type_constructor(Name,
% [])`, or `unknown`) has no derivable members, so yields none.
module_member_types(record_type(Fields, _Tail), MemberDefinitionTypes) :- !,
  findall(MemberName - MemberType,
          member(record_field(_, label(MemberName), MemberType), Fields),
          MemberDefinitionTypes).
module_member_types(_Other, []).

% Seed a term environment from the constructor schemes (each a `defined`
% binding usable anywhere), starting from the imported value environment.
constructor_environment([], Environment, Environment).
constructor_environment([Name - Scheme | Rest], EnvironmentIn, EnvironmentOut) :-
  put_assoc(Name, EnvironmentIn, defined(Scheme), Environment1),
  constructor_environment(Rest, Environment1, EnvironmentOut).

% ---------------------------------------------------------------------------
% Module-system normalisation and export collection
% ---------------------------------------------------------------------------

% Drop `use` items, unwrap `public` items, and record the exported names:
% value names from public definitions, and the full declaration node of each
% public `type` (its constructors are exported with it).
normalise_items([], [], [], []).
normalise_items([use_node(_, _, _) | Rest], CleanItems, ValueNames, TypeDeclarations) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
% A whole-module `use ./Math` seeds the environment directly (the loader has
% already entered every imported member under its qualified name), so like a
% named `use` it leaves no item behind for inference.
normalise_items([use_all_node(_, _) | Rest], CleanItems, ValueNames, TypeDeclarations) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
% Unwrapping `public` keeps the inner node's own spans (`NSpan`, `DSpan`, ...),
% so the lifted item still points at its source.  The `public` wrapper's own
% span is discarded -- it was only the `public` keyword prefix.
normalise_items([public_node(definition_node(identifier_node(Name, NSpan), Annotation, Value, DSpan), _) | Rest],
                [definition_node(identifier_node(Name, NSpan), Annotation, Value, DSpan) | CleanItems],
                [Name | ValueNames], TypeDeclarations) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
normalise_items([public_node(type_declaration_node(Name, Parameters, Opacity, Body, TSpan), _) | Rest],
                [type_declaration_node(Name, Parameters, Opacity, Body, TSpan) | CleanItems],
                ValueNames,
                [type_declaration_node(Name, Parameters, Opacity, Body, TSpan) | TypeDeclarations]) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
% A `public external` exports a value (its name); the external itself stays in
% the clean items so `seed_externals` binds it and codegen emits it.
normalise_items([public_node(external_node(Name, Type, Source, ESpan), _) | Rest],
                [external_node(Name, Type, Source, ESpan) | CleanItems],
                [Name | ValueNames], TypeDeclarations) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
% A module is an ordinary VALUE (see infer.pl's `module_node` inference); a
% `public module` exports its name exactly like a `public` definition would.
% A private (unqualified) module stays in the clean items unexported, same as
% any other private binding.
normalise_items([public_node(module_node(Name, Parameters, Opacity, Ascription, Items, MSpan), _) | Rest],
                [module_node(Name, Parameters, Opacity, Ascription, Items, MSpan) | CleanItems],
                [Name | ValueNames], TypeDeclarations) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
normalise_items([public_node(Other, _) | _], _, _, _) :- !,
  throw(analysis_error(cannot_export(Other))).
normalise_items([Item | Rest], [Item | CleanItems], ValueNames, TypeDeclarations) :-
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).

collect_exports(ValueNames, TypeDeclarations, FinalEnvironment, TypeEnvironment,
                ValueEntries, TypeEntries) :-
  export_values(ValueNames, FinalEnvironment, ValueValueEntries),
  export_types(TypeDeclarations, FinalEnvironment, TypeEnvironment, TypeValueEntries, TypeEntries),
  append(ValueValueEntries, TypeValueEntries, ValueEntries).

% Each exported value contributes its generalised scheme; a scheme with free
% (un-generalised) unification variables is ambiguous and may not cross a
% module boundary, so it is rejected with a clear error.
export_values([], _Environment, []).
export_values([Name | Names], Environment, [Name - defined(Scheme) | Rest]) :-
  get_assoc(Name, Environment, defined(Scheme)),
  scheme_free_unification_variables(Scheme, FreeIds),
  ( FreeIds == [] ->
      true
  ; throw(analysis_error(ambiguous_export(Name)))
  ),
  export_values(Names, Environment, Rest).

% Each exported type contributes its `TypeEnvironment` info; a tagged union
% additionally contributes every constructor's `constructor_key/1` info (a type
% entry) and its value scheme (a value entry) -- unless the union is `opaque`
% (abstract): then only the type name crosses the file boundary, so importers
% can annotate with the type but neither construct nor match its values.
export_types([], _Environment, _TypeEnvironment, [], []).
export_types([type_declaration_node(Name, _Parameters, Opacity, Body, _) | Declarations],
             Environment, TypeEnvironment, ValueEntries, TypeEntries) :-
  get_assoc(Name, TypeEnvironment, Info),
  ( Opacity == opaque ->
      ConstructorValueEntries = [], ConstructorTypeEntries = []
  ; export_constructors(Body, Environment, TypeEnvironment, ConstructorValueEntries, ConstructorTypeEntries)
  ),
  export_types(Declarations, Environment, TypeEnvironment, RestValueEntries, RestTypeEntries),
  append(ConstructorValueEntries, RestValueEntries, ValueEntries),
  append([Name - Info | ConstructorTypeEntries], RestTypeEntries, TypeEntries).

export_constructors(variant_body(Constructors), Environment, TypeEnvironment,
                    ValueEntries, TypeEntries) :- !,
  export_constructor_list(Constructors, Environment, TypeEnvironment, ValueEntries, TypeEntries).
export_constructors(_OtherBody, _Environment, _TypeEnvironment, [], []).

export_constructor_list([], _Environment, _TypeEnvironment, [], []).
export_constructor_list([constructor(CtorName, _Fields, _) | Rest], Environment, TypeEnvironment,
                        [CtorName - defined(CtorScheme) | RestValueEntries],
                        [constructor_key(CtorName) - CtorInfo | RestTypeEntries]) :-
  get_assoc(CtorName, Environment, defined(CtorScheme)),
  get_assoc(constructor_key(CtorName), TypeEnvironment, CtorInfo),
  export_constructor_list(Rest, Environment, TypeEnvironment, RestValueEntries, RestTypeEntries).
