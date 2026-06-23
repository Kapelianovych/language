:- module(analyser, [analyse/2]).

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
:- use_module(analyser/types, [
  empty_context/1,
  fully_resolve/3,
  context_substitution/2
]).
:- use_module(analyser/type_environment, [build_type_environment/3]).
:- use_module(analyser/infer, [infer_program/5]).

%% analyse(+AST, -Result).
%
% `Result` is `analysis_result(Type, Substitution)` where `Type` is the
% fully-resolved principal type of the program and `Substitution` is the
% solved part of the final algorithmic context as a list `Id = Type`.
%
% Before inference we collect and validate every `type` declaration into a
% `TypeEnvironment` (so annotations resolve to monotypes) and seed the term
% environment with every tagged-union constructor as a value.
analyse(AST, analysis_result(Type, Substitution)) :-
  build_type_environment(AST, TypeEnvironment, ConstructorBindings),
  constructor_environment(ConstructorBindings, InitialEnvironment),
  empty_context(Context0),
  infer_program(AST, TypeEnvironment, InitialEnvironment, Context0, program_type(LastType, Context)),
  fully_resolve(LastType, Context, Type),
  context_substitution(Context, Substitution).

% Seed a term environment from the constructor schemes (each a `defined`
% binding usable anywhere).
constructor_environment(ConstructorBindings, Environment) :-
  empty_assoc(Empty),
  constructor_environment(ConstructorBindings, Empty, Environment).

constructor_environment([], Environment, Environment).
constructor_environment([Name - Scheme | Rest], EnvironmentIn, EnvironmentOut) :-
  put_assoc(Name, EnvironmentIn, defined(Scheme), Environment1),
  constructor_environment(Rest, Environment1, EnvironmentOut).
