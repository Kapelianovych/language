:- module(module_transformation, [expand_modules/2]).

/*  transformation/module.pl  --  Erase nested `module Name = ( ... )` declarations.

    This is one of the compiler's source-to-source TRANSFORMATIONS (see the
    sibling `transformation/macro.pl`).  A transformation rewrites the parsed
    AST into a simpler AST before type-checking, so that the downstream stages
    (analyser, generator) never have to know the higher-level construct existed.

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

value_binder(definition_node(identifier_node(Name, _), _, _, _), Name).
value_binder(public_node(definition_node(identifier_node(Name, _), _, _, _), _), Name).
value_binder(external_node(Name, _, _, _), Name).
value_binder(public_node(external_node(Name, _, _, _), _), Name).

type_binder(Item, Name, Body) :-
  ( Item = type_declaration_node(Name, _Parameters, _Opacity, Body, _)
  ; Item = public_node(type_declaration_node(Name, _Parameters, _Opacity, Body, _), _)
  ).

submodule_binder(module_node(Name, _, _), Name).
submodule_binder(public_node(module_node(Name, _, _), _), Name).

submodule_body(module_node(_, Body, _), Body).
submodule_body(public_node(module_node(_, Body, _), _), Body).

is_public(public_node(_, _)).

% The only non-defining item a module body may contain.
allowed_module_item(use_node(_, _, _)).

% The constructor names a (variant) type-declaration body introduces.
body_constructor_names(variant_body(Constructors), Names) :-
  !,
  findall(Name, member(constructor(Name, _Fields, _), Constructors), Names).
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

expand_top_item(public_node(module_node(Name, Body, _), _), ctx(_, _, _, MS, _, NS), Output) :- !,
  expand_module_items([Name], Body, true, [], [], [], MS, NS, Output).
expand_top_item(module_node(Name, Body, _), ctx(_, _, _, MS, _, NS), Output) :- !,
  expand_module_items([Name], Body, false, [], [], [], MS, NS, Output).
expand_top_item(public_node(definition_node(Id, Ann, Value, DSpan), PSpan), Ctx,
                [public_node(definition_node(Id, Ann1, Value1, DSpan), PSpan)]) :- !,
  rewrite_annotation(Ann, Ctx, Ann1),
  rewrite(Value, Ctx, Value1).
expand_top_item(definition_node(Id, Ann, Value, DSpan), Ctx,
                [definition_node(Id, Ann1, Value1, DSpan)]) :- !,
  rewrite_annotation(Ann, Ctx, Ann1),
  rewrite(Value, Ctx, Value1).
expand_top_item(destructuring_node(Pattern, Value, DSpan), Ctx,
                [destructuring_node(Pattern, Value1, DSpan)]) :- !,
  rewrite(Value, Ctx, Value1).
expand_top_item(external_node(N, T, S, ESpan), Ctx, [external_node(N, T1, S, ESpan)]) :- !,
  rewrite_type(T, Ctx, T1).
expand_top_item(public_node(external_node(N, T, S, ESpan), PSpan), Ctx, [public_node(external_node(N, T1, S, ESpan), PSpan)]) :- !,
  rewrite_type(T, Ctx, T1).
% Top-level type declarations and `use`s pass through unchanged (a top-level
% type can reference only top-level / imported types, never an intra-file
% module type, which would need qualified-type syntax the loader handles).
expand_top_item(type_declaration_node(A, B, C, D, Span), _Ctx, [type_declaration_node(A, B, C, D, Span)]) :- !.
expand_top_item(public_node(type_declaration_node(A, B, C, D, Span), PSpan), _Ctx,
                [public_node(type_declaration_node(A, B, C, D, Span), PSpan)]) :- !.
expand_top_item(use_node(Path, Names, Span), _Ctx, [use_node(Path, Names, Span)]) :- !.
expand_top_item(use_all_node(Path, Span), _Ctx, [use_all_node(Path, Span)]) :- !.
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
% The lifted identifier keeps the member's ORIGINAL name span (`NSpan`) and the
% definition keeps its own span (`DSpan`), so the qualified `Math.add` still
% points at the source `add`.
expand_module_item(Item, Exported, Ctx, Output) :-
  ( Item = definition_node(identifier_node(Name, NSpan), Ann, Value, DSpan)
  ; Item = public_node(definition_node(identifier_node(Name, NSpan), Ann, Value, DSpan), _)
  ), !,
  Ctx = ctx(_, _, _, _, Prefix, _),
  append(Prefix, [Name], Seg), join_dotted(Seg, QualifiedName),
  rewrite_annotation(Ann, Ctx, Ann1),
  rewrite(Value, Ctx, Value1),
  wrap_export(Item, Exported, definition_node(identifier_node(QualifiedName, NSpan), Ann1, Value1, DSpan), DSpan, Output).
% A foreign binding -> a top-level external with a qualified name.
expand_module_item(Item, Exported, Ctx, Output) :-
  ( Item = external_node(Name, Type, Source, ESpan)
  ; Item = public_node(external_node(Name, Type, Source, ESpan), _)
  ), !,
  Ctx = ctx(_, _, _, _, Prefix, _),
  append(Prefix, [Name], Seg), join_dotted(Seg, QualifiedName),
  rewrite_type(Type, Ctx, Type1),
  wrap_export(Item, Exported, external_node(QualifiedName, Type1, Source, ESpan), ESpan, Output).
% A type declaration -> a top-level declaration with the type name AND every
% constructor name qualified, and field / body type expressions rewritten.
expand_module_item(Item, Exported, Ctx, Output) :-
  type_binder(Item, Name, Body), !,
  ( Item = type_declaration_node(Name, Parameters, Opacity, Body, TSpan)
  ; Item = public_node(type_declaration_node(Name, Parameters, Opacity, Body, TSpan), _)
  ),
  Ctx = ctx(_, _, _, _, Prefix, _),
  append(Prefix, [Name], TypeSeg), join_dotted(TypeSeg, QualifiedName),
  rewrite_type_body(Body, Parameters, Prefix, Ctx, Body1),
  wrap_export(Item, Exported, type_declaration_node(QualifiedName, Parameters, Opacity, Body1, TSpan), TSpan, Output).
% A `use` is lifted unchanged.
expand_module_item(use_node(Path, Names, Span), _Exported, _Ctx, [use_node(Path, Names, Span)]) :- !.
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

% Wrap a lifted item in `public_node` iff it should leave the file.  The
% synthesized wrapper is given the lifted node's own `Span` (the `public_node`
% span is not used downstream, but keeping it a real span preserves the
% node-shape invariant).
wrap_export(Item, Exported, Lifted, Span, [public_node(Lifted, Span)]) :-
  Exported, is_public(Item), !.
wrap_export(_Item, _Exported, Lifted, _Span, [Lifted]).

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
rewrite_constructors([constructor(Name, FieldTypes, CSpan) | Rest], Prefix, Ctx,
                     [constructor(QualifiedName, FieldTypes1, CSpan) | Rest1]) :-
  append(Prefix, [Name], Seg), join_dotted(Seg, QualifiedName),
  rewrite_type_list(FieldTypes, Ctx, FieldTypes1),
  rewrite_constructors(Rest, Prefix, Ctx, Rest1).

% ---------------------------------------------------------------------------
% Reference rewriting over an expression.
% ---------------------------------------------------------------------------

rewrite(number_node(N, S), _Ctx, number_node(N, S)) :- !.
rewrite(boolean_node(B, S), _Ctx, boolean_node(B, S)) :- !.
rewrite(placeholder_node(S), _Ctx, placeholder_node(S)) :- !.

rewrite(identifier_node(Name, S), ctx(VS, _, _, MS, _, _), Output) :- !,
  ( memberchk(Name - Seg, VS) ->
      join_dotted(Seg, Qualified), Output = identifier_node(Qualified, S)
  ; memberchk(Name - _, MS) ->
      throw(analysis_error(module_used_as_value(Name)))
  ; Output = identifier_node(Name, S)
  ).

rewrite(string_node(Parts, S), Ctx, string_node(Parts1, S)) :- !,
  rewrite_string_parts(Parts, Ctx, Parts1).

% Lambda: type parameters shadow module types (in parameter / return / body
% annotations); value parameters shadow members (in the body).
rewrite(function_node(TypeParameters, Parameters, ReturnAnnotation, Body, S), Ctx,
        function_node(TypeParameters, Parameters1, ReturnAnnotation1, Body1, S)) :- !,
  type_parameter_names(TypeParameters, TypeNames),
  shrink_types(Ctx, TypeNames, CtxT),
  rewrite_parameters(Parameters, CtxT, Parameters1),
  rewrite_annotation(ReturnAnnotation, CtxT, ReturnAnnotation1),
  parameters_vars(Parameters, Bound),
  shrink_values(CtxT, Bound, CtxTV),
  rewrite(Body, CtxTV, Body1).

rewrite(function_call_node(Target, Arguments, S), Ctx,
        function_call_node(Target1, Arguments1, S)) :- !,
  rewrite(Target, Ctx, Target1),
  rewrite_arguments(Arguments, Ctx, Arguments1).

rewrite(tuple_node(Members, S), Ctx, tuple_node(Members1, S)) :- !,
  rewrite_tuple_members(Members, Ctx, Members1).

rewrite(access_node(Target, Accessor, S), Ctx, Output) :- !,
  rewrite_access(access_node(Target, Accessor, S), Ctx, Output).

rewrite(assignment_node(Access, Value, S), Ctx, assignment_node(Access1, Value1, S)) :- !,
  rewrite(Access, Ctx, AccessRewritten),
  ( AccessRewritten = access_node(_, _, _) ->
      Access1 = AccessRewritten
  ; throw(analysis_error(cannot_assign_module_member))
  ),
  rewrite(Value, Ctx, Value1).

rewrite(block_node(Expressions, S), Ctx, block_node(Expressions1, S)) :- !,
  block_local_names(Expressions, Locals),
  shrink_values(Ctx, Locals, Ctx1),
  rewrite_list(Expressions, Ctx1, Expressions1).

rewrite(match_node(Scrutinee, Arms, S), Ctx, match_node(Scrutinee1, Arms1, S)) :- !,
  rewrite(Scrutinee, Ctx, Scrutinee1),
  rewrite_arms(Arms, Ctx, Arms1).

rewrite(conditional_node(C, T, E, S), Ctx, conditional_node(C1, T1, E1, S)) :- !,
  rewrite(C, Ctx, C1), rewrite(T, Ctx, T1), rewrite(E, Ctx, E1).
rewrite(unary_node(Op, E, S), Ctx, unary_node(Op, E1, S)) :- !,
  rewrite(E, Ctx, E1).
rewrite(binary_node(Op, L, R, S), Ctx, binary_node(Op, L1, R1, S)) :- !,
  rewrite(L, Ctx, L1), rewrite(R, Ctx, R1).
rewrite(definition_node(Id, Ann, V, S), Ctx, definition_node(Id, Ann1, V1, S)) :- !,
  rewrite_annotation(Ann, Ctx, Ann1), rewrite(V, Ctx, V1).
rewrite(destructuring_node(P, V, S), Ctx, destructuring_node(P, V1, S)) :- !,
  rewrite(V, Ctx, V1).
rewrite(type_declaration_node(N, P, O, B, S), _Ctx, type_declaration_node(N, P, O, B, S)) :- !.

rewrite_list([], _Ctx, []).
rewrite_list([E | Es], Ctx, [E1 | Es1]) :-
  rewrite(E, Ctx, E1), rewrite_list(Es, Ctx, Es1).

rewrite_arguments([], _Ctx, []).
rewrite_arguments([placeholder_node(S) | Rest], Ctx, [placeholder_node(S) | Rest1]) :- !,
  rewrite_arguments(Rest, Ctx, Rest1).
rewrite_arguments([Argument | Rest], Ctx, [Argument1 | Rest1]) :-
  rewrite(Argument, Ctx, Argument1), rewrite_arguments(Rest, Ctx, Rest1).

rewrite_tuple_members([], _Ctx, []).
rewrite_tuple_members([spread_member(V, S) | Rest], Ctx, [spread_member(V1, S) | Rest1]) :- !,
  rewrite(V, Ctx, V1), rewrite_tuple_members(Rest, Ctx, Rest1).
rewrite_tuple_members([tuple_member(Mut, Label, Ann, V, S) | Rest], Ctx,
                      [tuple_member(Mut, Label, Ann1, V1, S) | Rest1]) :-
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
rewrite_parameters([parameter_node(Pattern, Ann, S) | Rest], Ctx,
                   [parameter_node(Pattern, Ann1, S) | Rest1]) :-
  rewrite_annotation(Ann, Ctx, Ann1),
  rewrite_parameters(Rest, Ctx, Rest1).

% Each match arm: constructor names in the (or-)patterns are qualified; the
% pattern's bound variables shadow members in the guard and result.
rewrite_arms([], _Ctx, []).
rewrite_arms([match_arm(Patterns, Guard, Result, S) | Rest], Ctx,
             [match_arm(Patterns1, Guard1, Result1, S) | Rest1]) :-
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

rewrite_pattern(wildcard_pattern(S), _Ctx, wildcard_pattern(S)) :- !.
rewrite_pattern(binding_pattern(Name, S), _Ctx, binding_pattern(Name, S)) :- !.
rewrite_pattern(literal_pattern(Node, S), Ctx, literal_pattern(Node1, S)) :- !,
  rewrite(Node, Ctx, Node1).
rewrite_pattern(constructor_pattern(Name, SubPatterns, S), Ctx,
                constructor_pattern(QualifiedName, SubPatterns1, S)) :- !,
  Ctx = ctx(_, _, CS, _, _, _),
  ( memberchk(Name - Seg, CS) -> join_dotted(Seg, QualifiedName) ; QualifiedName = Name ),
  rewrite_patterns(SubPatterns, Ctx, SubPatterns1).
rewrite_pattern(record_pattern(Members, S), Ctx, record_pattern(Members1, S)) :- !,
  rewrite_pattern_members(Members, Ctx, Members1).

rewrite_pattern_members([], _Ctx, []).
rewrite_pattern_members([positional_member_pattern(P, S) | Rest], Ctx,
                        [positional_member_pattern(P1, S) | Rest1]) :- !,
  rewrite_pattern(P, Ctx, P1),
  rewrite_pattern_members(Rest, Ctx, Rest1).
rewrite_pattern_members([labeled_member_pattern(Label, P, S) | Rest], Ctx,
                        [labeled_member_pattern(Label, P1, S) | Rest1]) :-
  rewrite_pattern(P, Ctx, P1),
  rewrite_pattern_members(Rest, Ctx, Rest1).

% ---------------------------------------------------------------------------
% Type-expression rewriting: qualify bare module type names; a `Sub.T` chain is
% not yet expressible in the type grammar (the loader handles imported `M.T`).
% ---------------------------------------------------------------------------

rewrite_annotation(no_annotation, _Ctx, no_annotation).
rewrite_annotation(type_annotation(Type), Ctx, type_annotation(Type1)) :-
  rewrite_type(Type, Ctx, Type1).

rewrite_type(type_name_node(Name, Arguments, S), Ctx, type_name_node(Name1, Arguments1, S)) :- !,
  Ctx = ctx(_, TS, _, _, _, _),
  ( memberchk(Name - Seg, TS) -> join_dotted(Seg, Name1) ; Name1 = Name ),
  rewrite_type_arguments(Arguments, Ctx, Arguments1).
rewrite_type(tuple_type_node(Members, Openness, S), Ctx, tuple_type_node(Members1, Openness, S)) :- !,
  rewrite_type_members(Members, Ctx, Members1).
rewrite_type(function_type_node(Parameters, Return, S), Ctx,
             function_type_node(Parameters1, Return1, S)) :- !,
  rewrite_type_list(Parameters, Ctx, Parameters1),
  rewrite_type(Return, Ctx, Return1).
rewrite_type(quantified_type_node(Parameters, Body, S), Ctx,
             quantified_type_node(Parameters, Body1, S)) :- !,
  type_parameter_names(Parameters, Names),
  shrink_types(Ctx, Names, Ctx1),
  rewrite_type(Body, Ctx1, Body1).
rewrite_type(type_hole(S), _Ctx, type_hole(S)) :- !.

rewrite_type_list([], _Ctx, []).
rewrite_type_list([T | Ts], Ctx, [T1 | Ts1]) :-
  rewrite_type(T, Ctx, T1), rewrite_type_list(Ts, Ctx, Ts1).

rewrite_type_arguments([], _Ctx, []).
rewrite_type_arguments([type_hole(S) | Rest], Ctx, [type_hole(S) | Rest1]) :- !,
  rewrite_type_arguments(Rest, Ctx, Rest1).
rewrite_type_arguments([Argument | Rest], Ctx, [Argument1 | Rest1]) :-
  rewrite_type(Argument, Ctx, Argument1),
  rewrite_type_arguments(Rest, Ctx, Rest1).

rewrite_type_members([], _Ctx, []).
rewrite_type_members([tuple_type_member(Mut, Label, Type, S) | Rest], Ctx,
                     [tuple_type_member(Mut, Label, Type1, S) | Rest1]) :-
  rewrite_type(Type, Ctx, Type1),
  rewrite_type_members(Rest, Ctx, Rest1).

% ---------------------------------------------------------------------------
% Qualified value access resolution (`A.B.x`).
% ---------------------------------------------------------------------------

% `FullSpan` is the span of the whole access expression.  Collapsing a module
% access chain into a flat qualified identifier (or rebuilding a plain access
% chain) reuses that span for the synthesized identifier / access nodes -- the
% per-link spans are lost in flattening, but the whole chain is one source
% expression, so its span is a faithful location.
rewrite_access(access_node(Target, Accessor, FullSpan), ctx(VS, TS, CS, MS, Prefix, NS), Output) :-
  flatten_access(access_node(Target, Accessor, FullSpan), Base, Accessors),
  ( Base = identifier_node(Name, _),
    \+ memberchk(Name - _, VS),
    memberchk(Name - BaseSeg, MS)
  ->
    walk_module_path(BaseSeg, Accessors, Prefix, NS, FullSpan, Output)
  ;
    rewrite(Base, ctx(VS, TS, CS, MS, Prefix, NS), Base1),
    rebuild_access(Base1, Accessors, FullSpan, Output)
  ).

flatten_access(access_node(Target, Accessor, _Span), Base, Accessors) :- !,
  flatten_access(Target, Base, Inner),
  append(Inner, [Accessor], Accessors).
flatten_access(Node, Node, []).

rebuild_access(Base, [], _Span, Base).
rebuild_access(Base, [Accessor | Rest], Span, Output) :-
  rebuild_access(access_node(Base, Accessor, Span), Rest, Span, Output).

walk_module_path(Prefix, [], _CurrentPrefix, _NS, _Span, _) :-
  join_dotted(Prefix, Text),
  throw(analysis_error(module_used_as_value(Text))).
walk_module_path(Prefix, [label(Label, _) | Rest], CurrentPrefix,
                 ns(ValueMembers, TypeMembers, Modules, Publics), Span, Output) :- !,
  append(Prefix, [Label], Candidate),
  ( memberchk(Candidate, ValueMembers) ->
      require_accessible(Candidate, CurrentPrefix, Publics, inaccessible_member),
      join_dotted(Candidate, Qualified),
      rebuild_access(identifier_node(Qualified, Span), Rest, Span, Output)
  ; memberchk(Candidate, Modules) ->
      require_accessible(Candidate, CurrentPrefix, Publics, inaccessible_module),
      walk_module_path(Candidate, Rest, CurrentPrefix,
                       ns(ValueMembers, TypeMembers, Modules, Publics), Span, Output)
  ;
      join_dotted(Candidate, Text),
      throw(analysis_error(unknown_member(Text)))
  ).
walk_module_path(Prefix, [index(_, _) | _], _CurrentPrefix, _NS, _Span, _) :-
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
type_parameter_names([type_parameter(Name, _Kind, _Bound, _) | Rest], [Name | Names]) :-
  type_parameter_names(Rest, Names).

parameters_vars([], []).
parameters_vars([parameter_node(Pattern, _Annotation, _) | Rest], Vars) :-
  pattern_vars(Pattern, PatternVars),
  parameters_vars(Rest, RestVars),
  append(PatternVars, RestVars, Vars).

patterns_vars([], []).
patterns_vars([Pattern | Rest], Vars) :-
  pattern_vars(Pattern, PatternVars),
  patterns_vars(Rest, RestVars),
  append(PatternVars, RestVars, Vars).

pattern_vars(wildcard_pattern(_), []).
pattern_vars(binding_pattern(Name, _), [Name]).
pattern_vars(literal_pattern(_, _), []).
pattern_vars(constructor_pattern(_Name, SubPatterns, _), Vars) :-
  patterns_vars(SubPatterns, Vars).
pattern_vars(record_pattern(Members, _), Vars) :-
  pattern_member_vars(Members, Vars).

pattern_member_vars([], []).
pattern_member_vars([Member | Rest], Vars) :-
  ( Member = positional_member_pattern(SubPattern, _)
  ; Member = labeled_member_pattern(_Label, SubPattern, _)
  ),
  pattern_vars(SubPattern, MemberVars),
  pattern_member_vars(Rest, RestVars),
  append(MemberVars, RestVars, Vars).

block_local_names([], []).
block_local_names([definition_node(identifier_node(Name, _), _, _, _) | Rest], [Name | Names]) :- !,
  block_local_names(Rest, Names).
block_local_names([destructuring_node(Pattern, _, _) | Rest], Names) :- !,
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
% Dedup on path + imported names only: two identical lifted imports from
% different module bodies carry DIFFERENT spans, so the node itself is no longer
% a usable dedup key.  The first occurrence (with its span) is kept.
dedup_uses([use_node(Path, Names, Span) | Rest], Seen, Output) :- !,
  ( memberchk(named_use(Path, Names), Seen) -> Output = Output1
  ; Output = [use_node(Path, Names, Span) | Output1]
  ),
  dedup_uses(Rest, [named_use(Path, Names) | Seen], Output1).
dedup_uses([use_all_node(Path, Span) | Rest], Seen, Output) :- !,
  ( memberchk(whole_use(Path), Seen) -> Output = Output1
  ; Output = [use_all_node(Path, Span) | Output1]
  ),
  dedup_uses(Rest, [whole_use(Path) | Seen], Output1).
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
