:- module(namespace_import, [
  namespace_of/2,
  seed_namespace/9,
  collapse_namespace_access/4,
  rewrite_constructor_tags/3
]).

/*  namespace_import.pl  --  Whole-module imports (`use ./Math`).

    A `use ./Math` (no `:(...)` list) brings EVERY public item of the imported
    module into scope under a namespace, so they are reached as `Math.add`,
    `Math.Option`, `Math.Some`, ... -- without naming them one by one.  The
    namespace is the imported file's base name.

    Unlike nested modules (resolved entirely intra-file by `module_expander`),
    this needs the dependency's compiled INTERFACE -- which member names exist,
    and their types -- so it runs in the module loader, after the dependency is
    analysed.

    NAMESPACING THE INTERFACE.  The imported names are seeded under qualified
    local names (`Math.Option`), and the imported types/constructors are
    RE-QUALIFIED to match: a nominal type `Option` in the interface becomes
    `Math.Option` everywhere it appears (in constructor schemes, in variant
    info, in field type expressions), so two modules' `Option`s stay distinct
    nominal types and a `match` on `Math.Some`/`Math.None` checks against the
    re-qualified constructor set.  Only the dependency's OWN exported type names
    are re-qualified; a type it merely re-uses from a third module keeps its
    name (transitive nominal identity across three files is out of scope).

    RUNTIME.  Values and constructors are emitted as a renamed ES import,
    `import { $Some as $Math$Some } from "./Math.js"`, so `Math.Some` resolves
    to the dependency's binding.  A constructor's runtime `$tag`, however, is
    fixed in the dependency (`"Some"`), so `match`-arm constructor patterns are
    rewritten back from the local alias to that intrinsic tag for code
    generation (`rewrite_constructor_tags`).
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).

% ---------------------------------------------------------------------------
% Namespace name = the path's last segment (`./util/math` -> "math").
% ---------------------------------------------------------------------------

namespace_of(Path, Namespace) :-
  reverse(Path, Reversed),
  ( append(SegmentReversed, ['/' | _], Reversed) ->
      reverse(SegmentReversed, Namespace)
  ; Namespace = Path
  ).

% ---------------------------------------------------------------------------
% Seeding the value / type environments from a dependency's interface.
%
% seed_namespace(+Namespace, +Interface, +VIn, +TIn,
%                -VOut, -TOut, -Renames, -MemberNames, -ConstructorTags)
%
%   Renames          [Foreign - Local] runtime import pairs (values+ctors)
%   MemberNames      local qualified VALUE member names (for access collapse)
%   ConstructorTags  [Local - Foreign] for constructors (for tag rewrite)
% ---------------------------------------------------------------------------

seed_namespace(Namespace, module_interface(ValueEntries, TypeEntries), VIn, TIn,
               VOut, TOut, Renames, MemberNames, ConstructorTags) :-
  exported_type_names(TypeEntries, ExportedTypeNames),
  seed_values(ValueEntries, Namespace, ExportedTypeNames, VIn, VOut, Renames, MemberNames),
  seed_types(TypeEntries, Namespace, ExportedTypeNames, TIn, TOut, ConstructorTags).

% Names of declared types (the non-`constructor_key` keys of the interface).
exported_type_names([], []).
exported_type_names([constructor_key(_) - _ | Rest], Names) :- !,
  exported_type_names(Rest, Names).
exported_type_names([Name - _ | Rest], [Name | Names]) :-
  exported_type_names(Rest, Names).

seed_values([], _Namespace, _Exported, V, V, [], []).
seed_values([Name - defined(Scheme) | Rest], Namespace, Exported, VIn, VOut,
            [Name - Local | Renames], [Local | MemberNames]) :-
  qualify(Namespace, Name, Local),
  prefix_scheme(Scheme, Exported, Namespace, Scheme1),
  put_assoc(Local, VIn, defined(Scheme1), V1),
  seed_values(Rest, Namespace, Exported, V1, VOut, Renames, MemberNames).

seed_types([], _Namespace, _Exported, T, T, []).
seed_types([constructor_key(Name) - Info | Rest], Namespace, Exported, TIn, TOut, ConstructorTags) :- !,
  qualify(Namespace, Name, Local),
  prefix_constructor_info(Info, Exported, Namespace, Info1),
  put_assoc(constructor_key(Local), TIn, Info1, T1),
  ConstructorTags = [Local - Name | RestTags],
  seed_types(Rest, Namespace, Exported, T1, TOut, RestTags).
seed_types([Name - Info | Rest], Namespace, Exported, TIn, TOut, ConstructorTags) :-
  qualify(Namespace, Name, Local),
  prefix_type_info(Info, Exported, Namespace, Info1),
  put_assoc(Local, TIn, Info1, T1),
  seed_types(Rest, Namespace, Exported, T1, TOut, ConstructorTags).

qualify(Namespace, Name, Local) :-
  append(Namespace, ['.' | Name], Joined),
  canonical_chars(Joined, Local).

% Rebuild as fresh cons cells (see `plain_chars/2` in `identifier.pl`):
% qualified names must share ONE representation everywhere so they match as
% `assoc` keys regardless of where they were built.  (An `atom_chars` round
% trip does NOT suffice -- it keeps a partial-string backing.)
canonical_chars([], []).
canonical_chars([Character | Characters], [Character | Rest]) :-
  canonical_chars(Characters, Rest).

% --- Re-qualify the interned type info -------------------------------------

prefix_constructor_info(variant_constructor(Union, Parameters, FieldExpressions), Exported, Namespace,
                        variant_constructor(Union1, Parameters, FieldExpressions1)) :-
  prefix_type_name(Union, Exported, Namespace, Union1),
  maplist_surface(FieldExpressions, Exported, Namespace, FieldExpressions1).

prefix_type_info(type_variant_info(Parameters, Constructors), Exported, Namespace,
                 type_variant_info(Parameters, Constructors1)) :- !,
  prefix_variant_constructors(Constructors, Exported, Namespace, Constructors1).
prefix_type_info(type_declaration_info(Opacity, Parameters, Body), Exported, Namespace,
                 type_declaration_info(Opacity, Parameters, Body1)) :-
  prefix_surface(Body, Exported, Namespace, Body1).

prefix_variant_constructors([], _Exported, _Namespace, []).
prefix_variant_constructors([constructor(Name, FieldExpressions) | Rest], Exported, Namespace,
                            [constructor(Name1, FieldExpressions1) | Rest1]) :-
  prefix_constructor_name(Name, Namespace, Name1),
  maplist_surface(FieldExpressions, Exported, Namespace, FieldExpressions1),
  prefix_variant_constructors(Rest, Exported, Namespace, Rest1).

% A constructor name is ALWAYS re-qualified (it belongs to the imported module).
prefix_constructor_name(Name, Namespace, Local) :- qualify(Namespace, Name, Local).

% A type name is re-qualified only if it is one of the imported module's own
% exported types (not a builtin, a parameter, or a type it re-uses elsewhere).
prefix_type_name(Name, Exported, Namespace, Local) :-
  ( memberchk(Name, Exported) -> qualify(Namespace, Name, Local) ; Local = Name ).

% --- Surface type expressions (constructor field types, alias bodies) ------

maplist_surface([], _Exported, _Namespace, []).
maplist_surface([Type | Types], Exported, Namespace, [Type1 | Types1]) :-
  prefix_surface(Type, Exported, Namespace, Type1),
  maplist_surface(Types, Exported, Namespace, Types1).

prefix_surface(type_name_node(Name, Arguments), Exported, Namespace, type_name_node(Name1, Arguments1)) :- !,
  prefix_type_name(Name, Exported, Namespace, Name1),
  prefix_surface_arguments(Arguments, Exported, Namespace, Arguments1).
prefix_surface(tuple_type_node(Members, Openness), Exported, Namespace, tuple_type_node(Members1, Openness)) :- !,
  prefix_surface_members(Members, Exported, Namespace, Members1).
prefix_surface(function_type_node(Parameters, Return), Exported, Namespace,
               function_type_node(Parameters1, Return1)) :- !,
  maplist_surface(Parameters, Exported, Namespace, Parameters1),
  prefix_surface(Return, Exported, Namespace, Return1).
prefix_surface(quantified_type_node(Parameters, Body), Exported, Namespace,
               quantified_type_node(Parameters, Body1)) :- !,
  prefix_surface(Body, Exported, Namespace, Body1).
prefix_surface(type_hole, _Exported, _Namespace, type_hole) :- !.

prefix_surface_arguments([], _Exported, _Namespace, []).
prefix_surface_arguments([type_hole | Rest], Exported, Namespace, [type_hole | Rest1]) :- !,
  prefix_surface_arguments(Rest, Exported, Namespace, Rest1).
prefix_surface_arguments([Argument | Rest], Exported, Namespace, [Argument1 | Rest1]) :-
  prefix_surface(Argument, Exported, Namespace, Argument1),
  prefix_surface_arguments(Rest, Exported, Namespace, Rest1).

prefix_surface_members([], _Exported, _Namespace, []).
prefix_surface_members([tuple_type_member(Mut, Label, Type) | Rest], Exported, Namespace,
                       [tuple_type_member(Mut, Label, Type1) | Rest1]) :-
  prefix_surface(Type, Exported, Namespace, Type1),
  prefix_surface_members(Rest, Exported, Namespace, Rest1).

% --- Internal monotypes (constructor / value schemes) ----------------------

prefix_scheme(type_scheme(Ids, Body), Exported, Namespace, type_scheme(Ids, Body1)) :-
  prefix_mono(Body, Exported, Namespace, Body1).

prefix_mono(type_constructor(Name, Arguments), Exported, Namespace, type_constructor(Name1, Arguments1)) :- !,
  prefix_type_name(Name, Exported, Namespace, Name1),
  prefix_mono_list(Arguments, Exported, Namespace, Arguments1).
prefix_mono(constructor_ref(Name), Exported, Namespace, constructor_ref(Name1)) :- !,
  prefix_type_name(Name, Exported, Namespace, Name1).
prefix_mono(function_type(Parameters, Return), Exported, Namespace, function_type(Parameters1, Return1)) :- !,
  prefix_mono_list(Parameters, Exported, Namespace, Parameters1),
  prefix_mono(Return, Exported, Namespace, Return1).
prefix_mono(tuple_type(Fields, Tail), Exported, Namespace, tuple_type(Fields1, Tail1)) :- !,
  prefix_mono_fields(Fields, Exported, Namespace, Fields1),
  prefix_mono(Tail, Exported, Namespace, Tail1).
prefix_mono(forall_type(Ids, Body), Exported, Namespace, forall_type(Ids, Body1)) :- !,
  prefix_mono(Body, Exported, Namespace, Body1).
prefix_mono(type_lambda(Ids, Body), Exported, Namespace, type_lambda(Ids, Body1)) :- !,
  prefix_mono(Body, Exported, Namespace, Body1).
prefix_mono(type_application(Head, Arguments), Exported, Namespace, type_application(Head1, Arguments1)) :- !,
  prefix_mono(Head, Exported, Namespace, Head1),
  prefix_mono_list(Arguments, Exported, Namespace, Arguments1).
% Base types, quantified variables, skolems, closed tail, unification vars: as-is.
prefix_mono(Other, _Exported, _Namespace, Other).

prefix_mono_list([], _Exported, _Namespace, []).
prefix_mono_list([Type | Types], Exported, Namespace, [Type1 | Types1]) :-
  prefix_mono(Type, Exported, Namespace, Type1),
  prefix_mono_list(Types, Exported, Namespace, Types1).

prefix_mono_fields([], _Exported, _Namespace, []).
prefix_mono_fields([tuple_field(Mut, Key, Type) | Rest], Exported, Namespace,
                   [tuple_field(Mut, Key, Type1) | Rest1]) :-
  prefix_mono(Type, Exported, Namespace, Type1),
  prefix_mono_fields(Rest, Exported, Namespace, Rest1).

% ---------------------------------------------------------------------------
% AST rewrite 1: collapse a VALUE access whose base is an import namespace into
% one qualified identifier (`Math.add` -> identifier_node("Math.add")).  The
% member boundary is found by the LONGEST prefix of the label chain that is a
% known member name, so `Math.point.x` becomes `(Math.point).x` (field access
% on a member) while `Math.Inner.thing` collapses whole when `Inner.thing` is a
% public submodule member.
%
% A generic term walk recurses everywhere else, so every expression / pattern /
% type position is covered without enumerating node kinds.  (Local bindings
% that shadow a namespace name are not tracked -- a deliberately rare clash.)
% ---------------------------------------------------------------------------

collapse_namespace_access(Term, Bases, Members, Output) :-
  ( Term = access_node(_, _),
    flatten_access(Term, identifier_node(Name), Accessors),
    memberchk(Name, Bases)
  ->
    collapse_path(Name, Accessors, Members, Output)
  ; generic_map(collapse_namespace_access(_, Bases, Members, _), Term, Output)
  ).

collapse_path(Prefix, Accessors, Members, Output) :-
  longest_member(Prefix, Accessors, Members, MemberName, Rest),
  canonical_chars(MemberName, CanonicalName),
  rebuild_access(identifier_node(CanonicalName), Rest, Output).

% Find the longest label-prefix of `Accessors` that, joined onto `Prefix`, is a
% known member name.  Falls back to consuming the first label (so an unknown
% member surfaces later as an unbound reference rather than here).
longest_member(Prefix, Accessors, Members, MemberName, Rest) :-
  longest_member(Prefix, Accessors, Members, none, MemberName, Rest).

longest_member(Current, [label(Label) | More], Members, Best, MemberName, Rest) :-
  !,
  append(Current, ['.' | Label], Candidate),
  ( memberchk(Candidate, Members) ->
      longest_member(Candidate, More, Members, found(Candidate, More), MemberName, Rest)
  ; longest_member(Candidate, More, Members, Best, MemberName, Rest)
  ).
longest_member(_Current, _Remaining, _Members, found(MemberName, Rest), MemberName, Rest) :- !.
longest_member(Current, [_NonLabel | _] , _Members, none, Current, []) :- !. % index after a namespace: best effort
longest_member(Current, [], _Members, none, Current, []).

% ---------------------------------------------------------------------------
% AST rewrite 2: rewrite an imported constructor PATTERN's name from its local
% alias back to its intrinsic tag, for code generation only.  `Map` is
% [Local - Foreign]; a locally-defined (nested-module) constructor is absent
% from the map and keeps its qualified name (which is also its tag).
% ---------------------------------------------------------------------------

rewrite_constructor_tags(Term, Map, Output) :-
  ( Term = constructor_pattern(Name, SubPatterns)
  ->
    ( memberchk(Name - Foreign, Map) -> Name1 = Foreign ; Name1 = Name ),
    rewrite_constructor_tags_list(SubPatterns, Map, SubPatterns1),
    Output = constructor_pattern(Name1, SubPatterns1)
  ; generic_map(rewrite_constructor_tags(_, Map, _), Term, Output)
  ).

rewrite_constructor_tags_list([], _Map, []).
rewrite_constructor_tags_list([P | Ps], Map, [P1 | Ps1]) :-
  rewrite_constructor_tags(P, Map, P1),
  rewrite_constructor_tags_list(Ps, Map, Ps1).

% ---------------------------------------------------------------------------
% Shared helpers
% ---------------------------------------------------------------------------

flatten_access(access_node(Target, Accessor), Base, Accessors) :- !,
  flatten_access(Target, Base, Inner),
  append(Inner, [Accessor], Accessors).
flatten_access(Node, Node, []).

rebuild_access(Base, [], Base).
rebuild_access(Base, [Accessor | Rest], Output) :-
  rebuild_access(access_node(Base, Accessor), Rest, Output).

% Apply a 4-arg rewrite goal (with the first/last args as the per-subterm
% in/out holes) to every immediate argument of a compound term, leaving atomic
% terms untouched.  `Goal` is a partial application `g(_, Fixed.., _)`.
generic_map(Goal, Term, Output) :-
  ( compound(Term) ->
      Term =.. [Functor | Arguments],
      generic_map_arguments(Goal, Arguments, Arguments1),
      Output =.. [Functor | Arguments1]
  ; Output = Term
  ).

generic_map_arguments(_Goal, [], []).
generic_map_arguments(Goal, [Argument | Arguments], [Argument1 | Arguments1]) :-
  copy_goal(Goal, Argument, Argument1, Call),
  call(Call),
  generic_map_arguments(Goal, Arguments, Arguments1).

% `Goal` is a term like `collapse_namespace_access(_, Bases, Members, _)` whose
% first and last positions are placeholders; bind them to In / Out for one call.
copy_goal(Goal, In, Out, Call) :-
  Goal =.. [Name | Args],
  replace_ends(Args, In, Out, Args1),
  Call =.. [Name | Args1].

replace_ends(Args, In, Out, Args1) :-
  append([_First | Middle], [_Last], Args),
  append([In | Middle], [Out], Args1).
