:- module(constructor_pattern, [resolve_bare_constructors/3]).

/*  transformation/constructor_pattern.pl  --  Resolve BARE nullary
    constructor names in match patterns.

    A bare identifier in a match pattern parses as a `binding_pattern` (the
    parser cannot know which names are constructors).  This pass rewrites
    `binding_pattern(Name, Span)` into `constructor_pattern(Name, [], Span)`
    whenever `Name` is an in-scope NULLARY constructor, so `None => ..`
    matches the constructor without the `()` -- in typing, exhaustiveness
    checking, and code generation alike.  A name whose constructor takes
    fields stays a binding: matching such a constructor requires the
    parenthesised form, so the bare name is not ambiguous.

    THE RULE.  In match-pattern position a name is looked up in the
    CONSTRUCTOR namespace first; value bindings do not shadow it there (like
    Rust's path patterns).  The trade-off of dropping the parens: a typo of a
    nullary constructor's name silently becomes a catch-all binding -- the
    exhaustiveness check then reports later arms as already covered, which is
    the mitigating signal.

    SCOPE.  "In scope" here means the FILE's own top-level nullary
    constructors, plus the IMPORTED constructors seeded by the module loader
    / query engine, passed in as the seed type environment
    (`constructor_key/1` entries).  A nested `module` is a value, not erased,
    but this pass's own generic term walk (`resolve/3`) descends into its
    body like any other compound term, so a bare constructor name used
    inside a module's functions is resolved by this same pass -- no separate
    handling is needed.

    Patterns in IRREFUTABLE positions (function parameters, destructuring)
    are untouched: a constructor pattern can fail, so a bare name there is
    always a binding.  Only `match_arm` patterns are rewritten.
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).

% resolve_bare_constructors(+Program, +SeedTypeEnvironment, -Resolved).
%
% `SeedTypeEnvironment` is the assoc the analyser will be seeded with (empty
% for a single-file compile); its nullary `constructor_key/1` entries and the
% program's own top-level nullary constructors form the name set.
resolve_bare_constructors(program_node(Items), SeedTypeEnvironment, program_node(Items1)) :-
  local_nullary_constructors(Items, LocalNames),
  seeded_nullary_constructors(SeedTypeEnvironment, SeededNames),
  append(LocalNames, SeededNames, Names),
  ( Names == [] ->
      Items1 = Items
  ; resolve_list(Items, Names, Items1)
  ).

% Nullary constructors of the program's own top-level variant declarations.
% An `opaque` variant's constructors are matchable INSIDE the defining module
% (opacity binds importers only), so opacity is ignored here; imported opaque
% constructors never reach a seed environment in the first place (they are
% excluded from the module interface at export).
local_nullary_constructors([], []).
local_nullary_constructors([public_node(Item, _) | Rest], Names) :- !,
  local_nullary_constructors([Item | Rest], Names).
local_nullary_constructors([type_declaration_node(_Name, _Parameters, _Opacity, variant_body(Constructors), _) | Rest],
                           Names) :- !,
  nullary_names(Constructors, These),
  local_nullary_constructors(Rest, RestNames),
  append(These, RestNames, Names).
local_nullary_constructors([_Item | Rest], Names) :-
  local_nullary_constructors(Rest, Names).

nullary_names([], []).
nullary_names([constructor(Name, [], _) | Rest], [Name | Names]) :- !,
  nullary_names(Rest, Names).
nullary_names([_Constructor | Rest], Names) :-
  nullary_names(Rest, Names).

% Nullary constructors among the seeded imports.  (A whole-module import's
% constructors are seeded under dotted names -- those parse as constructor
% patterns already, so listing them here is harmless.)
seeded_nullary_constructors(TypeEnvironment, Names) :-
  assoc_to_list(TypeEnvironment, Entries),
  seeded_nullary(Entries, Names).

seeded_nullary([], []).
seeded_nullary([constructor_key(Name) - variant_constructor(_Union, _Parameters, []) | Rest],
               [Name | Names]) :- !,
  seeded_nullary(Rest, Names).
seeded_nullary([_Entry | Rest], Names) :-
  seeded_nullary(Rest, Names).

% A generic term walk (compare `namespace_import:generic_map/3`) that treats
% one shape specially: a `match_arm`'s patterns are rewritten in pattern
% mode, its guard and result recursively in term mode (they may hold nested
% matches).  Everything else is descended into structurally, so every
% expression position is covered without enumerating node kinds.
resolve(match_arm(Patterns, Guard, Result, Span), Names,
        match_arm(Patterns1, Guard1, Result1, Span)) :- !,
  resolve_patterns(Patterns, Names, Patterns1),
  resolve(Guard, Names, Guard1),
  resolve(Result, Names, Result1).
resolve(Term, Names, Output) :-
  ( compound(Term) ->
      Term =.. [Functor | Arguments],
      resolve_list(Arguments, Names, Arguments1),
      Output =.. [Functor | Arguments1]
  ; Output = Term
  ).

resolve_list([], _Names, []).
resolve_list([Term | Terms], Names, [Term1 | Terms1]) :-
  resolve(Term, Names, Term1),
  resolve_list(Terms, Names, Terms1).

resolve_patterns([], _Names, []).
resolve_patterns([Pattern | Patterns], Names, [Pattern1 | Patterns1]) :-
  resolve_pattern(Pattern, Names, Pattern1),
  resolve_patterns(Patterns, Names, Patterns1).

resolve_pattern(binding_pattern(Name, Span), Names, Output) :- !,
  ( memberchk(Name, Names) ->
      Output = constructor_pattern(Name, [], Span)
  ; Output = binding_pattern(Name, Span)
  ).
resolve_pattern(constructor_pattern(Name, SubPatterns, Span), Names,
                constructor_pattern(Name, SubPatterns1, Span)) :- !,
  resolve_patterns(SubPatterns, Names, SubPatterns1).
resolve_pattern(record_pattern(Members, Span), Names, record_pattern(Members1, Span)) :- !,
  resolve_members(Members, Names, Members1).
% Wildcards, literals, and error nodes: nothing to resolve.
resolve_pattern(Pattern, _Names, Pattern).

resolve_members([], _Names, []).
resolve_members([positional_member_pattern(Pattern, Span) | Rest], Names,
                [positional_member_pattern(Pattern1, Span) | Rest1]) :- !,
  resolve_pattern(Pattern, Names, Pattern1),
  resolve_members(Rest, Names, Rest1).
resolve_members([labeled_member_pattern(Label, Pattern, Span) | Rest], Names,
                [labeled_member_pattern(Label, Pattern1, Span) | Rest1]) :-
  resolve_pattern(Pattern, Names, Pattern1),
  resolve_members(Rest, Names, Rest1).
