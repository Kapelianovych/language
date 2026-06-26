:- module(module_expander, [expand_modules/2]).

/*  module_expander.pl  --  Erase nested `module Name = ( ... )` declarations.

    Nested modules are a COMPILE-TIME namespacing construct: a module is not a
    value, has no type, and cannot be passed around.  This pass runs between
    parsing and type-checking and rewrites the program so that nothing
    downstream (the type checker, the import resolver, the code generator) ever
    sees a `module_node` -- they all operate on ordinary, flat, QUALIFIED
    top-level items.

    WHAT A MODULE MAY CONTAIN

      value definitions, `external`s, `type` declarations (aliases and tagged
      unions), `use` imports, and further nested `module`s -- each optionally
      `public`.  A destructuring binding or a bare expression in a module body
      is rejected (it binds no name, or binds names a pattern cannot qualify).

    WHAT IT DOES

      * LIFTING.  Every named member is lifted to a top-level item under its
        dotted qualified path: inside `module Math = ( add = .. )`, `add`
        becomes a top-level definition named "Math.add"; a `type Shape` becomes
        "Math.Shape" and its constructor `Circle` becomes "Math.Circle".
        Members keep source order, so the forward-reference rules the type
        checker enforces over a sequence are preserved.

        A dotted name can never collide with a source identifier (identifiers
        are XID, admitting neither `.` nor `$`); the generator turns the `.`
        into `$` for a valid, equally-collision-free JS name.

      * THE TAG INVARIANT.  A tagged-union constructor's runtime `$tag` is its
        name, and the name is qualified on lifting, so `Math.Circle` has tag
        "Math.Circle".  Two modules may therefore each declare a `Circle`
        without their lifted constructors colliding -- the whole point of
        namespacing the tags.

      * REFERENCE REWRITING (shadow-aware) in three name spaces:
          values/constructors -- a bare `add`/`Circle` inside the module, or a
            qualified `Math.add`/`Sub.Circle` access chain, resolves to the
            lifted name;
          types               -- a bare type name in an annotation or in
            another declaration's body resolves to the lifted type;
          constructor patterns -- `Circle(r)` in a `match` arm resolves to the
            lifted constructor.
        A lambda parameter, block-local binding, or match-arm pattern shadows a
        VALUE/constructor of the same name; a function's or quantifier's type
        parameters shadow a TYPE of the same name.

      * VISIBILITY.  `public` makes a member reachable from outside its module;
        a private member is visible only within its module and that module's
        descendants.  A qualified access that crosses into a module from
        outside is checked against this rule.

      * EXPORT.  A top-level `public module` (and, transitively, the `public`
        members of `public` submodules) is EXPORTED from the file: such members
        are lifted wrapped in `public_node`, so the analyser collects them into
        the module interface under their qualified names.  Importers reach them
        with a whole-module `use ./File` (see the loader); the export names are
        qualified, so they cannot be named one-by-one in a `use (...)` list.

    REPRESENTATION

      A qualified name is a SEGMENT LIST: a list of name character-lists, so
      `Math.add` is `[[0'M,..],[0'a,..]]`.  It is `join_dotted`ed to a flat
      character list only when it becomes an `identifier_node` / type-name /
      constructor payload.

      The namespace is collected once into `ns(ValueMembers, TypeMembers,
      Modules, Publics)` -- four lists of segment lists (ValueMembers includes
      constructors, since those are reached through value access) -- so a
      qualified access can be validated against the whole module tree.

      A rewrite context is `ctx(ValueSubst, TypeSubst, ConstructorSubst,
      ModuleSubst, CurrentPrefix, NS)`, each *Subst a list of `ShortName -
      QualifiedSegmentList` pairs.  Inner scopes prepend bindings, so a
      `memberchk/2` finds the nearest (shadowing) binding first.
*/

:- use_module(library(lists)).

%% expand_modules(+ProgramIn, -ProgramOut).
%
% Idempotent: a program with no `module_node` is returned unchanged apart from
% de-duplicating identical lifted `use` imports.
expand_modules(program_node(Items), program_node(Output)) :-
  collect_namespace(Items, [], ns([], [], [], []), NS),
  direct_bindings(Items, [], _Values, _Types, _Constructors, TopModules),
  Ctx0 = ctx([], [], [], TopModules, [], NS),
  expand_top_items(Items, Ctx0, Lifted),
  dedup_uses(Lifted, Output).

% ---------------------------------------------------------------------------
% Item classification (each succeeds for the bare item and its `public` wrapper)
% ---------------------------------------------------------------------------

value_binder(definition_node(identifier_node(Name), _, _), Name).
value_binder(public_node(definition_node(identifier_node(Name), _, _)), Name).
value_binder(external_node(Name, _, _), Name).
value_binder(public_node(external_node(Name, _, _)), Name).

type_binder(Item, Name, Body) :-
  ( Item = type_declaration_node(Name, _Parameters, _Opacity, Body)
  ; Item = public_node(type_declaration_node(Name, _Parameters, _Opacity, Body))
  ).

submodule_binder(module_node(Name, _), Name).
submodule_binder(public_node(module_node(Name, _)), Name).

submodule_body(module_node(_, Body), Body).
submodule_body(public_node(module_node(_, Body)), Body).

is_public(public_node(_)).

% The only non-defining item a module body may contain.
allowed_module_item(use_node(_, _)).

% The constructor names a (variant) type-declaration body introduces.
body_constructor_names(variant_body(Constructors), Names) :-
  !,
  findall(Name, member(constructor(Name, _Fields), Constructors), Names).
body_constructor_names(_OtherBody, []).

% ---------------------------------------------------------------------------
% Pass 1: collect the whole module namespace.
% ---------------------------------------------------------------------------

collect_namespace([], _Prefix, NS, NS).
collect_namespace([Item | Rest], Prefix, NSin, NSout) :-
  collect_item(Item, Prefix, NSin, NS1),
  collect_namespace(Rest, Prefix, NS1, NSout).

collect_item(Item, Prefix, ns(V, T, Mod, P), NSout) :-
  submodule_binder(Item, Name), !,
  append(Prefix, [Name], Seg),
  publics_if(Item, Seg, P, P1),
  submodule_body(Item, Body),
  collect_namespace(Body, Seg, ns(V, T, [Seg | Mod], P1), NSout).
collect_item(Item, Prefix, ns(V, T, Mod, P), ns(V2, T2, Mod, P2)) :-
  Prefix \== [],
  type_binder(Item, Name, Body), !,
  append(Prefix, [Name], TypeSeg),
  publics_if(Item, TypeSeg, P, P1),
  body_constructor_names(Body, ConstructorNames),
  qualify_each(ConstructorNames, Prefix, ConstructorSegs),
  append(ConstructorSegs, V, V2),
  T2 = [TypeSeg | T],
  ( is_public(Item) -> append(ConstructorSegs, P1, P2) ; P2 = P1 ).
collect_item(Item, Prefix, ns(V, T, Mod, P), ns([Seg | V], T, Mod, P1)) :-
  Prefix \== [],
  value_binder(Item, Name), !,
  append(Prefix, [Name], Seg),
  publics_if(Item, Seg, P, P1).
collect_item(Item, Prefix, NS, NS) :-
  ( Prefix == [] -> true                 % a top-level non-module item: not a member
  ; allowed_module_item(Item) -> true
  ; throw(analysis_error(unsupported_module_item(Item)))
  ).

publics_if(Item, Seg, P, [Seg | P]) :- is_public(Item), !.
publics_if(_Item, _Seg, P, P).

qualify_each([], _Prefix, []).
qualify_each([Name | Names], Prefix, [Seg | Segs]) :-
  append(Prefix, [Name], Seg),
  qualify_each(Names, Prefix, Segs).

% ---------------------------------------------------------------------------
% Direct (one level deep) members of an item list, as short-name -> qualified-
% segment-list pairs.  ALL siblings are gathered before any body is rewritten,
% so a member may reference a sibling declared later.  Values include
% constructors (reached as values); constructors are also returned separately
% (for constructor-pattern resolution); types and submodules separately.
% ---------------------------------------------------------------------------

direct_bindings([], _Prefix, [], [], [], []).
direct_bindings([Item | Rest], Prefix, Values, Types, Constructors, Modules) :-
  ( submodule_binder(Item, Name) ->
      append(Prefix, [Name], Seg),
      Modules = [Name - Seg | Modules1],
      Values = Values1, Types = Types1, Constructors = Constructors1
  ; type_binder(Item, Name, Body) ->
      append(Prefix, [Name], TypeSeg),
      Types = [Name - TypeSeg | Types1],
      body_constructor_names(Body, ConstructorNames),
      pair_each(ConstructorNames, Prefix, ConstructorPairs),
      append(ConstructorPairs, Values1, Values),
      append(ConstructorPairs, Constructors1, Constructors),
      Modules = Modules1
  ; value_binder(Item, Name) ->
      append(Prefix, [Name], Seg),
      Values = [Name - Seg | Values1],
      Types = Types1, Constructors = Constructors1, Modules = Modules1
  ; Values = Values1, Types = Types1, Constructors = Constructors1, Modules = Modules1
  ),
  direct_bindings(Rest, Prefix, Values1, Types1, Constructors1, Modules1).

pair_each([], _Prefix, []).
pair_each([Name | Names], Prefix, [Name - Seg | Pairs]) :-
  append(Prefix, [Name], Seg),
  pair_each(Names, Prefix, Pairs).

% ---------------------------------------------------------------------------
% Pass 2a: file-level items.  Structure is preserved; only `module`s flatten,
% and every value-bearing sub-expression / annotation is rewritten so file-level
% `Module.member` references resolve.
% ---------------------------------------------------------------------------

expand_top_items([], _Ctx, []).
expand_top_items([Item | Rest], Ctx, Output) :-
  expand_top_item(Item, Ctx, Items1),
  expand_top_items(Rest, Ctx, Items2),
  append(Items1, Items2, Output).

expand_top_item(public_node(module_node(Name, Body)), ctx(_, _, _, MS, _, NS), Output) :- !,
  expand_module_items([Name], Body, true, [], [], [], MS, NS, Output).
expand_top_item(module_node(Name, Body), ctx(_, _, _, MS, _, NS), Output) :- !,
  expand_module_items([Name], Body, false, [], [], [], MS, NS, Output).
expand_top_item(public_node(definition_node(Id, Ann, Value)), Ctx,
                [public_node(definition_node(Id, Ann1, Value1))]) :- !,
  rewrite_annotation(Ann, Ctx, Ann1),
  rewrite(Value, Ctx, Value1).
expand_top_item(definition_node(Id, Ann, Value), Ctx,
                [definition_node(Id, Ann1, Value1)]) :- !,
  rewrite_annotation(Ann, Ctx, Ann1),
  rewrite(Value, Ctx, Value1).
expand_top_item(destructuring_node(Pattern, Value), Ctx,
                [destructuring_node(Pattern, Value1)]) :- !,
  rewrite(Value, Ctx, Value1).
expand_top_item(external_node(N, T, S), Ctx, [external_node(N, T1, S)]) :- !,
  rewrite_type(T, Ctx, T1).
expand_top_item(public_node(external_node(N, T, S)), Ctx, [public_node(external_node(N, T1, S))]) :- !,
  rewrite_type(T, Ctx, T1).
% Top-level type declarations and `use`s pass through unchanged (a top-level
% type can reference only top-level / imported types, never an intra-file
% module type, which would need qualified-type syntax the loader handles).
expand_top_item(type_declaration_node(A, B, C, D), _Ctx, [type_declaration_node(A, B, C, D)]) :- !.
expand_top_item(public_node(type_declaration_node(A, B, C, D)), _Ctx,
                [public_node(type_declaration_node(A, B, C, D))]) :- !.
expand_top_item(use_node(Path, Names), _Ctx, [use_node(Path, Names)]) :- !.
expand_top_item(use_all_node(Path), _Ctx, [use_all_node(Path)]) :- !.
% Any other top-level item is a bare expression: rewrite it in place.
expand_top_item(Other, Ctx, [Rewritten]) :-
  rewrite(Other, Ctx, Rewritten).

% ---------------------------------------------------------------------------
% Pass 2b: a module body.  Build the scope (this module's members layered over
% the enclosing scope), then lift each item to a qualified top-level item.
% `Exported` says whether members reachable from outside this module also leave
% the FILE -- true under a `public module` whose ancestors are all `public`.
% ---------------------------------------------------------------------------

expand_module_items(Prefix, Items, Exported, OuterValues, OuterTypes, OuterConstructors, OuterModules, NS, Output) :-
  direct_bindings(Items, Prefix, ValuePairs, TypePairs, ConstructorPairs, ModulePairs),
  append(ValuePairs, OuterValues, ValueSubst),
  append(TypePairs, OuterTypes, TypeSubst),
  append(ConstructorPairs, OuterConstructors, ConstructorSubst),
  append(ModulePairs, OuterModules, ModuleSubst),
  Ctx = ctx(ValueSubst, TypeSubst, ConstructorSubst, ModuleSubst, Prefix, NS),
  expand_module_list(Items, Exported, Ctx, Output).

expand_module_list([], _Exported, _Ctx, []).
expand_module_list([Item | Rest], Exported, Ctx, Output) :-
  expand_module_item(Item, Exported, Ctx, Items1),
  expand_module_list(Rest, Exported, Ctx, Items2),
  append(Items1, Items2, Output).

% A value member -> a top-level definition with a qualified name.
expand_module_item(Item, Exported, Ctx, Output) :-
  ( Item = definition_node(identifier_node(Name), Ann, Value)
  ; Item = public_node(definition_node(identifier_node(Name), Ann, Value))
  ), !,
  Ctx = ctx(_, _, _, _, Prefix, _),
  append(Prefix, [Name], Seg), join_dotted(Seg, QualifiedName),
  rewrite_annotation(Ann, Ctx, Ann1),
  rewrite(Value, Ctx, Value1),
  wrap_export(Item, Exported, definition_node(identifier_node(QualifiedName), Ann1, Value1), Output).
% A foreign binding -> a top-level external with a qualified name.
expand_module_item(Item, Exported, Ctx, Output) :-
  ( Item = external_node(Name, Type, Source)
  ; Item = public_node(external_node(Name, Type, Source))
  ), !,
  Ctx = ctx(_, _, _, _, Prefix, _),
  append(Prefix, [Name], Seg), join_dotted(Seg, QualifiedName),
  rewrite_type(Type, Ctx, Type1),
  wrap_export(Item, Exported, external_node(QualifiedName, Type1, Source), Output).
% A type declaration -> a top-level declaration with the type name AND every
% constructor name qualified, and field / body type expressions rewritten.
expand_module_item(Item, Exported, Ctx, Output) :-
  type_binder(Item, Name, Body), !,
  ( Item = type_declaration_node(Name, Parameters, Opacity, Body)
  ; Item = public_node(type_declaration_node(Name, Parameters, Opacity, Body))
  ),
  Ctx = ctx(_, _, _, _, Prefix, _),
  append(Prefix, [Name], TypeSeg), join_dotted(TypeSeg, QualifiedName),
  rewrite_type_body(Body, Parameters, Prefix, Ctx, Body1),
  wrap_export(Item, Exported, type_declaration_node(QualifiedName, Parameters, Opacity, Body1), Output).
% A `use` is lifted unchanged.
expand_module_item(use_node(Path, Names), _Exported, _Ctx, [use_node(Path, Names)]) :- !.
% A nested module recurses, narrowing the export flag.
expand_module_item(Item, Exported, Ctx, Output) :-
  submodule_binder(Item, Name), !,
  submodule_body(Item, Body),
  Ctx = ctx(VS, TS, CS, MS, Prefix, NS),
  append(Prefix, [Name], Seg),
  ( Exported, is_public(Item) -> Exported1 = true ; Exported1 = false ),
  expand_module_items(Seg, Body, Exported1, VS, TS, CS, MS, NS, Output).
expand_module_item(Item, _Exported, _Ctx, _) :-
  throw(analysis_error(unsupported_module_item(Item))).

% Wrap a lifted item in `public_node` iff it should leave the file.
wrap_export(Item, Exported, Lifted, [public_node(Lifted)]) :-
  Exported, is_public(Item), !.
wrap_export(_Item, _Exported, Lifted, [Lifted]).

% Rewrite a type-declaration body, with the declaration's own type parameters
% shadowing module type names, and constructor names qualified by `Prefix`.
rewrite_type_body(variant_body(Constructors), Parameters, Prefix, Ctx, variant_body(Constructors1)) :- !,
  type_parameter_names(Parameters, ParameterNames),
  shrink_types(Ctx, ParameterNames, Ctx1),
  rewrite_constructors(Constructors, Prefix, Ctx1, Constructors1).
rewrite_type_body(Body, Parameters, _Prefix, Ctx, Body1) :-
  type_parameter_names(Parameters, ParameterNames),
  shrink_types(Ctx, ParameterNames, Ctx1),
  rewrite_type(Body, Ctx1, Body1).

rewrite_constructors([], _Prefix, _Ctx, []).
rewrite_constructors([constructor(Name, FieldTypes) | Rest], Prefix, Ctx,
                     [constructor(QualifiedName, FieldTypes1) | Rest1]) :-
  append(Prefix, [Name], Seg), join_dotted(Seg, QualifiedName),
  rewrite_type_list(FieldTypes, Ctx, FieldTypes1),
  rewrite_constructors(Rest, Prefix, Ctx, Rest1).

% ---------------------------------------------------------------------------
% Reference rewriting over an expression.
% ---------------------------------------------------------------------------

rewrite(number_node(N), _Ctx, number_node(N)) :- !.
rewrite(boolean_node(B), _Ctx, boolean_node(B)) :- !.
rewrite(placeholder_node, _Ctx, placeholder_node) :- !.

rewrite(identifier_node(Name), ctx(VS, _, _, MS, _, _), Output) :- !,
  ( memberchk(Name - Seg, VS) ->
      join_dotted(Seg, Qualified), Output = identifier_node(Qualified)
  ; memberchk(Name - _, MS) ->
      throw(analysis_error(module_used_as_value(Name)))
  ; Output = identifier_node(Name)
  ).

rewrite(string_node(Parts), Ctx, string_node(Parts1)) :- !,
  rewrite_string_parts(Parts, Ctx, Parts1).

% Lambda: type parameters shadow module types (in parameter / return / body
% annotations); value parameters shadow members (in the body).
rewrite(function_node(TypeParameters, Parameters, ReturnAnnotation, Body), Ctx,
        function_node(TypeParameters, Parameters1, ReturnAnnotation1, Body1)) :- !,
  type_parameter_names(TypeParameters, TypeNames),
  shrink_types(Ctx, TypeNames, CtxT),
  rewrite_parameters(Parameters, CtxT, Parameters1),
  rewrite_annotation(ReturnAnnotation, CtxT, ReturnAnnotation1),
  parameters_vars(Parameters, Bound),
  shrink_values(CtxT, Bound, CtxTV),
  rewrite(Body, CtxTV, Body1).

rewrite(function_call_node(Target, Arguments), Ctx,
        function_call_node(Target1, Arguments1)) :- !,
  rewrite(Target, Ctx, Target1),
  rewrite_arguments(Arguments, Ctx, Arguments1).

rewrite(tuple_node(Members), Ctx, tuple_node(Members1)) :- !,
  rewrite_tuple_members(Members, Ctx, Members1).

rewrite(access_node(Target, Accessor), Ctx, Output) :- !,
  rewrite_access(access_node(Target, Accessor), Ctx, Output).

rewrite(assignment_node(Access, Value), Ctx, assignment_node(Access1, Value1)) :- !,
  rewrite(Access, Ctx, AccessRewritten),
  ( AccessRewritten = access_node(_, _) ->
      Access1 = AccessRewritten
  ; throw(analysis_error(cannot_assign_module_member))
  ),
  rewrite(Value, Ctx, Value1).

rewrite(block_node(Expressions), Ctx, block_node(Expressions1)) :- !,
  block_local_names(Expressions, Locals),
  shrink_values(Ctx, Locals, Ctx1),
  rewrite_list(Expressions, Ctx1, Expressions1).

rewrite(match_node(Scrutinee, Arms), Ctx, match_node(Scrutinee1, Arms1)) :- !,
  rewrite(Scrutinee, Ctx, Scrutinee1),
  rewrite_arms(Arms, Ctx, Arms1).

rewrite(conditional_node(C, T, E), Ctx, conditional_node(C1, T1, E1)) :- !,
  rewrite(C, Ctx, C1), rewrite(T, Ctx, T1), rewrite(E, Ctx, E1).
rewrite(unary_node(Op, E), Ctx, unary_node(Op, E1)) :- !,
  rewrite(E, Ctx, E1).
rewrite(binary_node(Op, L, R), Ctx, binary_node(Op, L1, R1)) :- !,
  rewrite(L, Ctx, L1), rewrite(R, Ctx, R1).
rewrite(definition_node(Id, Ann, V), Ctx, definition_node(Id, Ann1, V1)) :- !,
  rewrite_annotation(Ann, Ctx, Ann1), rewrite(V, Ctx, V1).
rewrite(destructuring_node(P, V), Ctx, destructuring_node(P, V1)) :- !,
  rewrite(V, Ctx, V1).
rewrite(type_declaration_node(N, P, O, B), _Ctx, type_declaration_node(N, P, O, B)) :- !.

rewrite_list([], _Ctx, []).
rewrite_list([E | Es], Ctx, [E1 | Es1]) :-
  rewrite(E, Ctx, E1), rewrite_list(Es, Ctx, Es1).

rewrite_arguments([], _Ctx, []).
rewrite_arguments([placeholder_node | Rest], Ctx, [placeholder_node | Rest1]) :- !,
  rewrite_arguments(Rest, Ctx, Rest1).
rewrite_arguments([Argument | Rest], Ctx, [Argument1 | Rest1]) :-
  rewrite(Argument, Ctx, Argument1), rewrite_arguments(Rest, Ctx, Rest1).

rewrite_tuple_members([], _Ctx, []).
rewrite_tuple_members([spread_member(V) | Rest], Ctx, [spread_member(V1) | Rest1]) :- !,
  rewrite(V, Ctx, V1), rewrite_tuple_members(Rest, Ctx, Rest1).
rewrite_tuple_members([tuple_member(Mut, Label, Ann, V) | Rest], Ctx,
                      [tuple_member(Mut, Label, Ann1, V1) | Rest1]) :-
  rewrite_annotation(Ann, Ctx, Ann1),
  rewrite(V, Ctx, V1),
  rewrite_tuple_members(Rest, Ctx, Rest1).

rewrite_string_parts([], _Ctx, []).
rewrite_string_parts([string_static_part(S) | Rest], Ctx, [string_static_part(S) | Rest1]) :- !,
  rewrite_string_parts(Rest, Ctx, Rest1).
rewrite_string_parts([string_interpolated_part(E) | Rest], Ctx,
                     [string_interpolated_part(E1) | Rest1]) :-
  rewrite(E, Ctx, E1), rewrite_string_parts(Rest, Ctx, Rest1).

rewrite_parameters([], _Ctx, []).
rewrite_parameters([parameter_node(Pattern, Ann) | Rest], Ctx,
                   [parameter_node(Pattern, Ann1) | Rest1]) :-
  rewrite_annotation(Ann, Ctx, Ann1),
  rewrite_parameters(Rest, Ctx, Rest1).

% Each match arm: constructor names in the (or-)patterns are qualified; the
% pattern's bound variables shadow members in the guard and result.
rewrite_arms([], _Ctx, []).
rewrite_arms([match_arm(Patterns, Guard, Result) | Rest], Ctx,
             [match_arm(Patterns1, Guard1, Result1) | Rest1]) :-
  rewrite_patterns(Patterns, Ctx, Patterns1),
  patterns_vars(Patterns, Bound),
  shrink_values(Ctx, Bound, Ctx1),
  rewrite_guard(Guard, Ctx1, Guard1),
  rewrite(Result, Ctx1, Result1),
  rewrite_arms(Rest, Ctx, Rest1).

rewrite_guard(no_guard, _Ctx, no_guard).
rewrite_guard(guard(E), Ctx, guard(E1)) :- rewrite(E, Ctx, E1).

% ---------------------------------------------------------------------------
% Pattern rewriting: qualify constructor names (a bare sibling constructor via
% the constructor substitution; a `Sub.Ctor` access chain via the namespace).
% ---------------------------------------------------------------------------

rewrite_patterns([], _Ctx, []).
rewrite_patterns([Pattern | Rest], Ctx, [Pattern1 | Rest1]) :-
  rewrite_pattern(Pattern, Ctx, Pattern1),
  rewrite_patterns(Rest, Ctx, Rest1).

rewrite_pattern(wildcard_pattern, _Ctx, wildcard_pattern) :- !.
rewrite_pattern(binding_pattern(Name), _Ctx, binding_pattern(Name)) :- !.
rewrite_pattern(literal_pattern(Node), Ctx, literal_pattern(Node1)) :- !,
  rewrite(Node, Ctx, Node1).
rewrite_pattern(constructor_pattern(Name, SubPatterns), Ctx,
                constructor_pattern(QualifiedName, SubPatterns1)) :- !,
  Ctx = ctx(_, _, CS, _, _, _),
  ( memberchk(Name - Seg, CS) -> join_dotted(Seg, QualifiedName) ; QualifiedName = Name ),
  rewrite_patterns(SubPatterns, Ctx, SubPatterns1).
rewrite_pattern(record_pattern(Members), Ctx, record_pattern(Members1)) :- !,
  rewrite_pattern_members(Members, Ctx, Members1).

rewrite_pattern_members([], _Ctx, []).
rewrite_pattern_members([positional_member_pattern(P) | Rest], Ctx,
                        [positional_member_pattern(P1) | Rest1]) :- !,
  rewrite_pattern(P, Ctx, P1),
  rewrite_pattern_members(Rest, Ctx, Rest1).
rewrite_pattern_members([labeled_member_pattern(Label, P) | Rest], Ctx,
                        [labeled_member_pattern(Label, P1) | Rest1]) :-
  rewrite_pattern(P, Ctx, P1),
  rewrite_pattern_members(Rest, Ctx, Rest1).

% ---------------------------------------------------------------------------
% Type-expression rewriting: qualify bare module type names; a `Sub.T` chain is
% not yet expressible in the type grammar (the loader handles imported `M.T`).
% ---------------------------------------------------------------------------

rewrite_annotation(no_annotation, _Ctx, no_annotation).
rewrite_annotation(type_annotation(Type), Ctx, type_annotation(Type1)) :-
  rewrite_type(Type, Ctx, Type1).

rewrite_type(type_name_node(Name, Arguments), Ctx, type_name_node(Name1, Arguments1)) :- !,
  Ctx = ctx(_, TS, _, _, _, _),
  ( memberchk(Name - Seg, TS) -> join_dotted(Seg, Name1) ; Name1 = Name ),
  rewrite_type_arguments(Arguments, Ctx, Arguments1).
rewrite_type(tuple_type_node(Members, Openness), Ctx, tuple_type_node(Members1, Openness)) :- !,
  rewrite_type_members(Members, Ctx, Members1).
rewrite_type(function_type_node(Parameters, Return), Ctx,
             function_type_node(Parameters1, Return1)) :- !,
  rewrite_type_list(Parameters, Ctx, Parameters1),
  rewrite_type(Return, Ctx, Return1).
rewrite_type(quantified_type_node(Parameters, Body), Ctx,
             quantified_type_node(Parameters, Body1)) :- !,
  type_parameter_names(Parameters, Names),
  shrink_types(Ctx, Names, Ctx1),
  rewrite_type(Body, Ctx1, Body1).
rewrite_type(type_hole, _Ctx, type_hole) :- !.

rewrite_type_list([], _Ctx, []).
rewrite_type_list([T | Ts], Ctx, [T1 | Ts1]) :-
  rewrite_type(T, Ctx, T1), rewrite_type_list(Ts, Ctx, Ts1).

rewrite_type_arguments([], _Ctx, []).
rewrite_type_arguments([type_hole | Rest], Ctx, [type_hole | Rest1]) :- !,
  rewrite_type_arguments(Rest, Ctx, Rest1).
rewrite_type_arguments([Argument | Rest], Ctx, [Argument1 | Rest1]) :-
  rewrite_type(Argument, Ctx, Argument1),
  rewrite_type_arguments(Rest, Ctx, Rest1).

rewrite_type_members([], _Ctx, []).
rewrite_type_members([tuple_type_member(Mut, Label, Type) | Rest], Ctx,
                     [tuple_type_member(Mut, Label, Type1) | Rest1]) :-
  rewrite_type(Type, Ctx, Type1),
  rewrite_type_members(Rest, Ctx, Rest1).

% ---------------------------------------------------------------------------
% Qualified value access resolution (`A.B.x`).
% ---------------------------------------------------------------------------

rewrite_access(Node, ctx(VS, TS, CS, MS, Prefix, NS), Output) :-
  flatten_access(Node, Base, Accessors),
  ( Base = identifier_node(Name),
    \+ memberchk(Name - _, VS),
    memberchk(Name - BaseSeg, MS)
  ->
    walk_module_path(BaseSeg, Accessors, Prefix, NS, Output)
  ;
    rewrite(Base, ctx(VS, TS, CS, MS, Prefix, NS), Base1),
    rebuild_access(Base1, Accessors, Output)
  ).

flatten_access(access_node(Target, Accessor), Base, Accessors) :- !,
  flatten_access(Target, Base, Inner),
  append(Inner, [Accessor], Accessors).
flatten_access(Node, Node, []).

rebuild_access(Base, [], Base).
rebuild_access(Base, [Accessor | Rest], Output) :-
  rebuild_access(access_node(Base, Accessor), Rest, Output).

walk_module_path(Prefix, [], _CurrentPrefix, _NS, _) :-
  join_dotted(Prefix, Text),
  throw(analysis_error(module_used_as_value(Text))).
walk_module_path(Prefix, [label(Label) | Rest], CurrentPrefix,
                 ns(ValueMembers, TypeMembers, Modules, Publics), Output) :- !,
  append(Prefix, [Label], Candidate),
  ( memberchk(Candidate, ValueMembers) ->
      require_accessible(Candidate, CurrentPrefix, Publics, inaccessible_member),
      join_dotted(Candidate, Qualified),
      rebuild_access(identifier_node(Qualified), Rest, Output)
  ; memberchk(Candidate, Modules) ->
      require_accessible(Candidate, CurrentPrefix, Publics, inaccessible_module),
      walk_module_path(Candidate, Rest, CurrentPrefix,
                       ns(ValueMembers, TypeMembers, Modules, Publics), Output)
  ;
      join_dotted(Candidate, Text),
      throw(analysis_error(unknown_member(Text)))
  ).
walk_module_path(Prefix, [index(_) | _], _CurrentPrefix, _NS, _) :-
  join_dotted(Prefix, Text),
  throw(analysis_error(module_has_no_positional_field(Text))).

require_accessible(Candidate, CurrentPrefix, Publics, ErrorTag) :-
  ( memberchk(Candidate, Publics) -> true
  ; append(Parent, [_Last], Candidate), append(Parent, _, CurrentPrefix) -> true
  ; join_dotted(Candidate, Text), Error =.. [ErrorTag, Text],
    throw(analysis_error(Error))
  ).

% ---------------------------------------------------------------------------
% Scope shrinking and bound-name extraction
% ---------------------------------------------------------------------------

% A value binder shadows values, constructors and module names.
shrink_values(ctx(VS, TS, CS, MS, Prefix, NS), Names,
              ctx(VS1, TS, CS1, MS1, Prefix, NS)) :-
  remove_keys(VS, Names, VS1),
  remove_keys(CS, Names, CS1),
  remove_keys(MS, Names, MS1).

% A type binder shadows type names only.
shrink_types(ctx(VS, TS, CS, MS, Prefix, NS), Names,
             ctx(VS, TS1, CS, MS, Prefix, NS)) :-
  remove_keys(TS, Names, TS1).

remove_keys([], _Names, []).
remove_keys([Key - Value | Rest], Names, Output) :-
  ( memberchk(Key, Names) -> Output = Output1 ; Output = [Key - Value | Output1] ),
  remove_keys(Rest, Names, Output1).

type_parameter_names([], []).
type_parameter_names([type_parameter(Name, _Kind, _Bound) | Rest], [Name | Names]) :-
  type_parameter_names(Rest, Names).

parameters_vars([], []).
parameters_vars([parameter_node(Pattern, _Annotation) | Rest], Vars) :-
  pattern_vars(Pattern, PatternVars),
  parameters_vars(Rest, RestVars),
  append(PatternVars, RestVars, Vars).

patterns_vars([], []).
patterns_vars([Pattern | Rest], Vars) :-
  pattern_vars(Pattern, PatternVars),
  patterns_vars(Rest, RestVars),
  append(PatternVars, RestVars, Vars).

pattern_vars(wildcard_pattern, []).
pattern_vars(binding_pattern(Name), [Name]).
pattern_vars(literal_pattern(_), []).
pattern_vars(constructor_pattern(_Name, SubPatterns), Vars) :-
  patterns_vars(SubPatterns, Vars).
pattern_vars(record_pattern(Members), Vars) :-
  pattern_member_vars(Members, Vars).

pattern_member_vars([], []).
pattern_member_vars([Member | Rest], Vars) :-
  ( Member = positional_member_pattern(SubPattern)
  ; Member = labeled_member_pattern(_Label, SubPattern)
  ),
  pattern_vars(SubPattern, MemberVars),
  pattern_member_vars(Rest, RestVars),
  append(MemberVars, RestVars, Vars).

block_local_names([], []).
block_local_names([definition_node(identifier_node(Name), _, _) | Rest], [Name | Names]) :- !,
  block_local_names(Rest, Names).
block_local_names([destructuring_node(Pattern, _) | Rest], Names) :- !,
  pattern_vars(Pattern, PatternVars),
  block_local_names(Rest, RestNames),
  append(PatternVars, RestNames, Names).
block_local_names([_Other | Rest], Names) :-
  block_local_names(Rest, Names).

% ---------------------------------------------------------------------------
% De-duplicate identical lifted `use` imports.
% ---------------------------------------------------------------------------

dedup_uses(Items, Output) :- dedup_uses(Items, [], Output).

dedup_uses([], _Seen, []).
dedup_uses([use_node(Path, Names) | Rest], Seen, Output) :- !,
  ( memberchk(use_node(Path, Names), Seen) -> Output = Output1
  ; Output = [use_node(Path, Names) | Output1]
  ),
  dedup_uses(Rest, [use_node(Path, Names) | Seen], Output1).
dedup_uses([use_all_node(Path) | Rest], Seen, Output) :- !,
  ( memberchk(use_all_node(Path), Seen) -> Output = Output1
  ; Output = [use_all_node(Path) | Output1]
  ),
  dedup_uses(Rest, [use_all_node(Path) | Seen], Output1).
dedup_uses([Item | Rest], Seen, [Item | Output1]) :-
  dedup_uses(Rest, Seen, Output1).

% ---------------------------------------------------------------------------
% Join a segment list (list of name char-lists) into one dotted char-list.
% ---------------------------------------------------------------------------

% Join a segment list into one dotted name, rebuilt as fresh cons cells so it
% shares one representation with parser-built names (see `plain_chars/2` in
% `identifier.pl`); otherwise the qualified key sorts inconsistently as an
% `assoc` key and lookups miss.
join_dotted(Segments, Name) :-
  join_dotted_raw(Segments, Raw),
  plain_chars(Raw, Name).

join_dotted_raw([Segment], Segment) :- !.
join_dotted_raw([Segment | Segments], Output) :-
  join_dotted_raw(Segments, Rest),
  append(Segment, ['.' | Rest], Output).

plain_chars([], []).
plain_chars([Character | Characters], [Character | Rest]) :-
  plain_chars(Characters, Rest).
