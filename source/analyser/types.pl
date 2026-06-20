:- module(types, [
  empty_context/1,
  fresh_uvar/4,
  resolve/3,
  zonk/3,
  unify/4,
  generalize/5,
  instantiate/5,
  monomorphic_scheme/2,
  context_substitution/2
]).

/*  types.pl  --  Type language + level-based algorithmic context.

    This module is the heart of the checker.  It implements the
    *level-based algorithmic type system* of Fan, Xu & Xie, "Practical
    Type Inference with Levels" (PLDI'25), specialised to the
    annotation-free, predicative Hindley-Milner fragment that our source
    language can actually express.  The generalisation / instantiation
    machinery follows Heeren, Hage & Swierstra, "Generalizing
    Hindley-Milner Type Inference Algorithms" (UU-CS-2002-031).

    --------------------------------------------------------------------
    THE TYPE LANGUAGE
    --------------------------------------------------------------------
    A monotype `tau` is one of:

        number                      base type of all numeric literals
        boolean                     base type of `true` / `false`
        string                      base type of string literals
        uvar(Id)                    a unification variable (`alpha^n` in
                                    the paper); its level and solution
                                    live in the algorithmic context
        function_type(Params, Ret)  an n-ary function `(t1 .. tn) -> r`
        tuple_type(Elems)           a tuple `(t1 .. tn)`  (Elems = [] is unit)

    A *type scheme* (the polytype assigned to a let/definition binding) is

        scheme(QVarIds, Body)

    where `Body` is a monotype in which each generalised variable appears
    as `qvar(Id)`.  `scheme([], Body)` is a trivial (monomorphic) scheme,
    used for lambda parameters which must NOT be generalised.

    --------------------------------------------------------------------
    THE ALGORITHMIC CONTEXT (Fig. 4 of the levels paper)
    --------------------------------------------------------------------
    Rather than relying on Prolog's own unification (which cannot carry
    levels), we make the algorithmic context `Gamma` explicit, exactly as
    the paper's mechanised system does.  It is represented as

        ctx(NextId, Store)

    `NextId` hands out fresh unification-variable identifiers.  `Store` is
    an AVL map (library(assoc)) from an identifier to either

        unsolved(Level)   -- an open variable `alpha^Level`
        solved(Type)      -- a resolved variable `alpha^Level = Type`

    The context is threaded through every judgement (`CtxIn` -> `CtxOut`),
    accumulating solutions, just like the input/output contexts
    `Gamma |- e => sigma -| Delta` of the algorithmic rules.
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).

%% empty_context(-Context).
%
% The initial algorithmic context: no variables, ids start at 0.
empty_context(ctx(0, Store)) :-
  empty_assoc(Store).

%% fresh_uvar(+CtxIn, +Level, -Uvar, -CtxOut).
%
% Allocate a fresh unification variable `alpha^Level` (rule AT-LAM /
% AM-FORALL: a new uvar is born at the *current* typing level, which
% bounds the level of whatever it may later be solved to).
fresh_uvar(ctx(Id, Store), Level, uvar(Id), ctx(Id1, Store1)) :-
  Id1 is Id + 1,
  put_assoc(Id, Store, unsolved(Level), Store1).

%% monomorphic_scheme(+Type, -Scheme).
%
% Wrap a monotype as a scheme with no quantifiers.  Looking such a scheme
% up and instantiating it returns the very same type (sharing its uvars),
% which is what we want for lambda-bound variables.
monomorphic_scheme(Type, scheme([], Type)).

% ---------------------------------------------------------------------------
% Resolution and zonking (context application `[Gamma]sigma`, Fig. 4)
% ---------------------------------------------------------------------------

%% resolve(+Type, +Ctx, -Resolved).
%
% Follow the chain of solved unification variables one *head* level deep:
% if `Type` is a solved uvar we return its (recursively resolved)
% solution, otherwise we return `Type` untouched.  The result is never a
% solved uvar.
resolve(Type, Ctx, Resolved) :-
  ( Type = uvar(Id) ->
      Ctx = ctx(_, Store),
      get_assoc(Id, Store, Entry),
      ( Entry = solved(Solution) ->
          resolve(Solution, Ctx, Resolved)
      ; Resolved = Type            % unsolved: stays as `uvar(Id)`
      )
  ; Resolved = Type
  ).

%% zonk(+Type, +Ctx, -Resolved).
%
% Deep context application: replace every solved unification variable by
% its solution, recursively, throughout the whole type.  This is `[Gamma]`
% applied as a substitution.
%
% "Zonk" is jargon borrowed from GHC's type checker: it is the (informal,
% onomatopoeic) name for forcing the accumulated variable->solution store
% through a type so that no solved variables remain.  It exists only at the
% algorithmic level -- in the declarative theory it is plain substitution;
% the name distinguishes "resolve everything now" from the lazy bindings
% that just sit in the context.
zonk(Type, Ctx, Resolved) :-
  resolve(Type, Ctx, Head),
  ( Head = function_type(Params, Ret) ->
      zonk_list(Params, Ctx, Params1),
      zonk(Ret, Ctx, Ret1),
      Resolved = function_type(Params1, Ret1)
  ; Head = tuple_type(Elems) ->
      zonk_list(Elems, Ctx, Elems1),
      Resolved = tuple_type(Elems1)
  ; Resolved = Head
  ).

zonk_list([], _, []).
zonk_list([T | Ts], Ctx, [Z | Zs]) :-
  zonk(T, Ctx, Z),
  zonk_list(Ts, Ctx, Zs).

% ---------------------------------------------------------------------------
% Unification with level adjustment (the algorithmic `<:` collapses to
% ordinary unification in this annotation-free fragment, Fig. 6)
% ---------------------------------------------------------------------------

%% unify(+Type1, +Type2, +CtxIn, -CtxOut).
%
% Make `Type1` and `Type2` equal, extending the context with the required
% variable solutions.  Throws `analysis_error(...)` on a clash.
unify(Type1, Type2, CtxIn, CtxOut) :-
  resolve(Type1, CtxIn, R1),
  resolve(Type2, CtxIn, R2),
  unify_resolved(R1, R2, CtxIn, CtxOut).

unify_resolved(uvar(Id), uvar(Id), Ctx, Ctx) :- !.       % already identical
unify_resolved(uvar(Id), Type, CtxIn, CtxOut) :- !,
  bind_uvar(Id, Type, CtxIn, CtxOut).
unify_resolved(Type, uvar(Id), CtxIn, CtxOut) :- !,
  bind_uvar(Id, Type, CtxIn, CtxOut).
unify_resolved(number, number, Ctx, Ctx) :- !.
unify_resolved(boolean, boolean, Ctx, Ctx) :- !.
unify_resolved(string, string, Ctx, Ctx) :- !.
unify_resolved(function_type(P1, R1), function_type(P2, R2), CtxIn, CtxOut) :- !,
  ( same_length(P1, P2) ->
      unify_list(P1, P2, CtxIn, Ctx1),
      unify(R1, R2, Ctx1, CtxOut)
  ; throw(analysis_error(function_arity_mismatch(P1, P2)))
  ).
unify_resolved(tuple_type(E1), tuple_type(E2), CtxIn, CtxOut) :- !,
  ( same_length(E1, E2) ->
      unify_list(E1, E2, CtxIn, CtxOut)
  ; throw(analysis_error(tuple_size_mismatch(E1, E2)))
  ).
unify_resolved(A, B, CtxIn, _) :-
  % No rule applies: a genuine type clash.  Report the fully-resolved
  % shapes so the message is informative.
  zonk(A, CtxIn, ZA),
  zonk(B, CtxIn, ZB),
  throw(analysis_error(type_mismatch(ZA, ZB))).

unify_list([], [], Ctx, Ctx).
unify_list([A | As], [B | Bs], CtxIn, CtxOut) :-
  unify(A, B, CtxIn, Ctx1),
  unify_list(As, Bs, Ctx1, CtxOut).

%% bind_uvar(+Id, +Type, +CtxIn, -CtxOut).
%
% Solve `alpha_Id := Type`.  Two invariants from the paper are enforced
% here:
%
%   * Occurs check -- `alpha_Id` must not appear inside `Type`, otherwise
%     we would be building an infinite type.
%
%   * Level adjustment (a.k.a. "promotion", rule PR-UVARPR and the OCaml
%     in-place update of section 7).  The solution of a level-`m` variable
%     may only mention variables of level <= m; any deeper variable inside
%     `Type` is lowered to `m`.  This single operation is what makes
%     level-based generalisation sound: it prevents a variable that should
%     stay monomorphic (or a would-be escaping skolem) from being
%     generalised at an outer scope.
bind_uvar(Id, Type, CtxIn, CtxOut) :-
  CtxIn = ctx(_, Store),
  get_assoc(Id, Store, unsolved(Level)),
  occurs_and_adjust(Id, Level, Type, CtxIn, ctx(NextId, Store1)),
  put_assoc(Id, Store1, solved(Type), Store2),
  CtxOut = ctx(NextId, Store2).

%% occurs_and_adjust(+Id, +MaxLevel, +Type, +CtxIn, -CtxOut).
%
% Walk `Type`; fail (throw) if `Id` occurs in it, and lower the level of
% every unsolved variable whose level exceeds `MaxLevel`.
occurs_and_adjust(Id, MaxLevel, Type, CtxIn, CtxOut) :-
  resolve(Type, CtxIn, R),
  ( R = uvar(Other) ->
      ( Other =:= Id ->
          throw(analysis_error(occurs_check(Id)))
      ; CtxIn = ctx(NextId, Store),
        get_assoc(Other, Store, unsolved(OtherLevel)),
        ( OtherLevel > MaxLevel ->
            put_assoc(Other, Store, unsolved(MaxLevel), Store1),
            CtxOut = ctx(NextId, Store1)
        ; CtxOut = CtxIn
        )
      )
  ; R = function_type(Params, Ret) ->
      occurs_and_adjust_list(Id, MaxLevel, Params, CtxIn, Ctx1),
      occurs_and_adjust(Id, MaxLevel, Ret, Ctx1, CtxOut)
  ; R = tuple_type(Elems) ->
      occurs_and_adjust_list(Id, MaxLevel, Elems, CtxIn, CtxOut)
  ; CtxOut = CtxIn                 % base type: nothing to do
  ).

occurs_and_adjust_list(_, _, [], Ctx, Ctx).
occurs_and_adjust_list(Id, MaxLevel, [T | Ts], CtxIn, CtxOut) :-
  occurs_and_adjust(Id, MaxLevel, T, CtxIn, Ctx1),
  occurs_and_adjust_list(Id, MaxLevel, Ts, Ctx1, CtxOut).

% ---------------------------------------------------------------------------
% Generalisation and instantiation (let-polymorphism, via levels)
% ---------------------------------------------------------------------------

%% generalize(+Type, +OuterLevel, +CtxIn, -Scheme, -CtxOut).
%
% Implements rule LT-LET / AT-LET generalisation `forall ftv^{n+1}(sigma)`.
% The body `e1` of a definition was inferred at `OuterLevel + 1`; here we
% quantify exactly those unification variables whose level is strictly
% greater than `OuterLevel`.
%
% The level discipline is precisely the efficiency win of the paper: a
% variable still has level > OuterLevel iff it was created inside this
% definition AND was never linked (by `bind_uvar`'s level adjustment) to
% anything from an enclosing scope.  So we never have to scan the typing
% environment to decide what is safe to generalise.
generalize(Type, OuterLevel, Ctx, scheme(QVarIds, Body), Ctx) :-
  zonk(Type, Ctx, Zonked),
  collect_uvar_ids(Zonked, [], AllIds),
  include_generalizable(AllIds, OuterLevel, Ctx, QVarIds),
  abstract_qvars(Zonked, QVarIds, Body).

% Collect, without duplicates, the ids of all (unsolved) uvars in a
% already-zonked type.
collect_uvar_ids(Type, Acc, Ids) :-
  ( Type = uvar(Id) ->
      ( memberchk(Id, Acc) -> Ids = Acc ; Ids = [Id | Acc] )
  ; Type = function_type(Params, Ret) ->
      collect_uvar_ids_list(Params, Acc, Acc1),
      collect_uvar_ids(Ret, Acc1, Ids)
  ; Type = tuple_type(Elems) ->
      collect_uvar_ids_list(Elems, Acc, Ids)
  ; Ids = Acc
  ).

collect_uvar_ids_list([], Acc, Acc).
collect_uvar_ids_list([T | Ts], Acc, Ids) :-
  collect_uvar_ids(T, Acc, Acc1),
  collect_uvar_ids_list(Ts, Acc1, Ids).

% Keep only those ids whose level is deeper than the enclosing scope.
include_generalizable([], _, _, []).
include_generalizable([Id | Ids], OuterLevel, Ctx, Result) :-
  Ctx = ctx(_, Store),
  get_assoc(Id, Store, unsolved(Level)),
  ( Level > OuterLevel ->
      Result = [Id | Rest]
  ; Result = Rest
  ),
  include_generalizable(Ids, OuterLevel, Ctx, Rest).

% Replace each generalised `uvar(Id)` by the bound variable `qvar(Id)`.
abstract_qvars(Type, QVarIds, Out) :-
  ( Type = uvar(Id) ->
      ( memberchk(Id, QVarIds) -> Out = qvar(Id) ; Out = Type )
  ; Type = function_type(Params, Ret) ->
      abstract_qvars_list(Params, QVarIds, Params1),
      abstract_qvars(Ret, QVarIds, Ret1),
      Out = function_type(Params1, Ret1)
  ; Type = tuple_type(Elems) ->
      abstract_qvars_list(Elems, QVarIds, Elems1),
      Out = tuple_type(Elems1)
  ; Out = Type
  ).

abstract_qvars_list([], _, []).
abstract_qvars_list([T | Ts], QVarIds, [O | Os]) :-
  abstract_qvars(T, QVarIds, O),
  abstract_qvars_list(Ts, QVarIds, Os).

%% instantiate(+Scheme, +Level, +CtxIn, -Type, -CtxOut).
%
% Replace every quantified variable of the scheme by a fresh unification
% variable born at the current typing `Level` (rule LT-VAR's use of a
% scheme, and `instantiate` of the HM paper).  A monomorphic scheme
% `scheme([], Body)` is returned verbatim, preserving variable sharing.
instantiate(scheme(QVarIds, Body), Level, CtxIn, Type, CtxOut) :-
  fresh_qvar_mapping(QVarIds, Level, CtxIn, Mapping, CtxOut),
  substitute_qvars(Body, Mapping, Type).

% Build a `QVarId-uvar(NewId)` map, allocating one fresh uvar per
% quantified variable.
fresh_qvar_mapping([], _, Ctx, [], Ctx).
fresh_qvar_mapping([Q | Qs], Level, CtxIn, [Q - Fresh | Rest], CtxOut) :-
  fresh_uvar(CtxIn, Level, Fresh, Ctx1),
  fresh_qvar_mapping(Qs, Level, Ctx1, Rest, CtxOut).

substitute_qvars(Type, Mapping, Out) :-
  ( Type = qvar(Q) ->
      ( memberchk(Q - Fresh, Mapping) -> Out = Fresh ; Out = Type )
  ; Type = function_type(Params, Ret) ->
      substitute_qvars_list(Params, Mapping, Params1),
      substitute_qvars(Ret, Mapping, Ret1),
      Out = function_type(Params1, Ret1)
  ; Type = tuple_type(Elems) ->
      substitute_qvars_list(Elems, Mapping, Elems1),
      Out = tuple_type(Elems1)
  ; Out = Type
  ).

substitute_qvars_list([], _, []).
substitute_qvars_list([T | Ts], Mapping, [O | Os]) :-
  substitute_qvars(T, Mapping, O),
  substitute_qvars_list(Ts, Mapping, Os).

% ---------------------------------------------------------------------------
% Reporting
% ---------------------------------------------------------------------------

%% context_substitution(+Ctx, -Substitution).
%
% Extract the solved part of the context as a list `Id = ResolvedType`,
% i.e. the final substitution produced by inference.
context_substitution(Ctx, Substitution) :-
  Ctx = ctx(_, Store),
  assoc_to_list(Store, Pairs),
  solved_pairs(Pairs, Ctx, Substitution).

solved_pairs([], _, []).
solved_pairs([Id - solved(Type) | Ps], Ctx, [Id = Zonked | Rest]) :- !,
  zonk(Type, Ctx, Zonked),
  solved_pairs(Ps, Ctx, Rest).
solved_pairs([_ - unsolved(_) | Ps], Ctx, Rest) :-
  solved_pairs(Ps, Ctx, Rest).
