:- module(analyser, [analyse/2, analyse_module/5]).

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
  generalize/5,
  scheme_free_unification_variables/2,
  context_substitution/2
]).
:- use_module(analyser/type_environment, [
  build_type_environment/4,
  convert_annotation_type/6
]).
:- use_module(analyser/infer, [infer_program/6]).
:- use_module(module_expander, [expand_modules/2]).
:- use_module(unicode, [xid_start/1, xid_continue/1]).

%% analyse(+AST, -Result).
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
  analyse_module(AST, EmptyValueEnvironment, EmptyTypeEnvironment, Result, _Interface).

%% analyse_module(+AST, +SeedValueEnvironment, +SeedTypeEnvironment, -Result, -Interface).
%
% Type-checks one module.  `SeedValueEnvironment` / `SeedTypeEnvironment` are
% assocs pre-populated by the module loader with the entries this module
% imports (values, type names, and `constructor_key/1` constructor entries).
% `Result` is the usual `analysis_result(Type, Substitution)`.  `Interface` is
% `module_interface(ValueEntries, TypeEntries)`: the assoc-ready entries this
% module makes `public`, ready to seed an importing module.
%
% Nested modules are erased first (`expand_modules`); then `public` wrappers are
% unwrapped and `use` / `use_all` declarations dropped before inference (the
% loader has already turned imports into seed entries); the set of exported
% names is remembered so the interface can be collected afterwards.
analyse_module(ProgramAst, SeedValueEnvironment, SeedTypeEnvironment,
               analysis_result(Type, Substitution),
               module_interface(ValueEntries, TypeEntries)) :-
  % Erase any nested modules first (idempotent: a flat program, e.g. one the
  % loader already expanded, is unchanged), so inference and export collection
  % only ever see flat, qualified top-level items.
  expand_modules(ProgramAst, program_node(Items)),
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

% Seed a term environment from the constructor schemes (each a `defined`
% binding usable anywhere), starting from the imported value environment.
constructor_environment([], Environment, Environment).
constructor_environment([Name - Scheme | Rest], EnvironmentIn, EnvironmentOut) :-
  put_assoc(Name, EnvironmentIn, defined(Scheme), Environment1),
  constructor_environment(Rest, Environment1, EnvironmentOut).

% Bind every `external Name: Type = ...` (foreign JS import) into the
% environment.  The ascribed `Type` is converted to a monotype and generalised
% into a scheme exactly as a top-level annotation would be -- there is no value
% to check it against, so the type is simply trusted (this is the one unsafe
% point of the JS boundary).  Binding them up front (before inference walks the
% items) makes every external visible throughout the module, like a constant.
% Non-`external` items are left for the inference walk.
seed_externals([], _TypeEnvironment, _Level, Environment, Context, Environment, Context).
seed_externals([external_node(Name, TypeExpression, Source) | Rest], TypeEnvironment, Level,
               EnvironmentIn, ContextIn, EnvironmentOut, ContextOut) :- !,
  validate_external_source(Source),
  Level1 is Level + 1,
  convert_annotation_type(TypeExpression, TypeEnvironment, Level1, ContextIn, MonoType, Context1),
  generalize(MonoType, Level, Context1, Scheme, Context2),
  put_assoc(Name, EnvironmentIn, defined(Scheme), Environment1),
  seed_externals(Rest, TypeEnvironment, Level, Environment1, Context2, EnvironmentOut, ContextOut).
seed_externals([_Other | Rest], TypeEnvironment, Level, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut) :-
  seed_externals(Rest, TypeEnvironment, Level, EnvironmentIn, ContextIn, EnvironmentOut, ContextOut).

% A renamed module import (`= 'foreign' from 'module'`) names a JS export that
% codegen splices, unescaped, into `import { Foreign } from ...` -- so it must
% be a valid JS identifier or it would break (or inject into) the emitted
% import.  The other source forms put no name in identifier position: a
% `js_global` / same-name `default` import reuses the (already-valid) declared
% name, and a `js_expression` is trusted verbatim.
validate_external_source(js_module(_Module, named(Foreign))) :- !,
  ( js_identifier(Foreign) -> true
  ; throw(analysis_error(invalid_external_name(Foreign)))
  ).
validate_external_source(_Source).

% A JS IdentifierName, on the language's own Unicode identifier basis (UAX #31
% XID_Start / XID_Continue, via `unicode`) plus the two characters JS allows
% that XID does not: `$` (in neither set) and a leading `_` (XID_Continue but
% not XID_Start).  So foreign names are exactly as permissive as the language's
% own identifiers.
js_identifier([First | Rest]) :-
  js_identifier_start(First),
  maplist(js_identifier_continue, Rest).

js_identifier_start(Char) :-
  char_code(Char, Code),
  ( Code =:= 0'_ ; Code =:= 0'$ ; xid_start(Code) ).

js_identifier_continue(Char) :-
  char_code(Char, Code),
  ( Code =:= 0'$ ; xid_continue(Code) ).   % `_` is already in XID_Continue

% ---------------------------------------------------------------------------
% Module-system normalisation and export collection
% ---------------------------------------------------------------------------

% Drop `use` items, unwrap `public` items, and record the exported names:
% value names from public definitions, and the full declaration node of each
% public `type` (its constructors are exported with it).
normalise_items([], [], [], []).
normalise_items([use_node(_, _) | Rest], CleanItems, ValueNames, TypeDeclarations) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
% A whole-module `use ./Math` seeds the environment directly (the loader has
% already entered every imported member under its qualified name), so like a
% named `use` it leaves no item behind for inference.
normalise_items([use_all_node(_) | Rest], CleanItems, ValueNames, TypeDeclarations) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
normalise_items([public_node(definition_node(identifier_node(Name), Annotation, Value)) | Rest],
                [definition_node(identifier_node(Name), Annotation, Value) | CleanItems],
                [Name | ValueNames], TypeDeclarations) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
normalise_items([public_node(type_declaration_node(Name, Parameters, Opacity, Body)) | Rest],
                [type_declaration_node(Name, Parameters, Opacity, Body) | CleanItems],
                ValueNames,
                [type_declaration_node(Name, Parameters, Opacity, Body) | TypeDeclarations]) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
% A `public external` exports a value (its name); the external itself stays in
% the clean items so `seed_externals` binds it and codegen emits it.
normalise_items([public_node(external_node(Name, Type, Source)) | Rest],
                [external_node(Name, Type, Source) | CleanItems],
                [Name | ValueNames], TypeDeclarations) :- !,
  normalise_items(Rest, CleanItems, ValueNames, TypeDeclarations).
normalise_items([public_node(Other) | _], _, _, _) :- !,
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
% entry) and its value scheme (a value entry).
export_types([], _Environment, _TypeEnvironment, [], []).
export_types([type_declaration_node(Name, _Parameters, _Opacity, Body) | Declarations],
             Environment, TypeEnvironment, ValueEntries, TypeEntries) :-
  get_assoc(Name, TypeEnvironment, Info),
  export_constructors(Body, Environment, TypeEnvironment, ConstructorValueEntries, ConstructorTypeEntries),
  export_types(Declarations, Environment, TypeEnvironment, RestValueEntries, RestTypeEntries),
  append(ConstructorValueEntries, RestValueEntries, ValueEntries),
  append([Name - Info | ConstructorTypeEntries], RestTypeEntries, TypeEntries).

export_constructors(variant_body(Constructors), Environment, TypeEnvironment,
                    ValueEntries, TypeEntries) :- !,
  export_constructor_list(Constructors, Environment, TypeEnvironment, ValueEntries, TypeEntries).
export_constructors(_OtherBody, _Environment, _TypeEnvironment, [], []).

export_constructor_list([], _Environment, _TypeEnvironment, [], []).
export_constructor_list([constructor(CtorName, _Fields) | Rest], Environment, TypeEnvironment,
                        [CtorName - defined(CtorScheme) | RestValueEntries],
                        [constructor_key(CtorName) - CtorInfo | RestTypeEntries]) :-
  get_assoc(CtorName, Environment, defined(CtorScheme)),
  get_assoc(constructor_key(CtorName), TypeEnvironment, CtorInfo),
  export_constructor_list(Rest, Environment, TypeEnvironment, RestValueEntries, RestTypeEntries).
