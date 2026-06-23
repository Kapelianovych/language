:- module(match, [match//2]).

/*  match.pl  --  `match` expressions.

        match <scrutinee>
        | <pattern> => <result>
        | <pattern> if <guard> => <result>
        | _ => <result>

    An arm may list several alternative patterns (an OR-PATTERN), separated
    by `|`, sharing one guard and result:

        | Circle(r) | Square(r) => r

    Produced AST:

        match_node(Scrutinee, Arms)
            arm: match_arm(Patterns, Guard, Result)   -- Patterns is non-empty
            Guard: no_guard | guard(Expression)

    `match` is a soft keyword.  The scrutinee is parsed as a full expression;
    the parser relies on backtracking to stop it before the first arm's `|`
    (which would otherwise be read as the binary `|` operator).
*/

:- use_module(library(dcgs)).
:- use_module(pattern, [pattern//2]).
:- use_module(postfix, [postfix//2]).
:- use_module(separator, [
  separator//0,
  separators//0
]).

:- meta_predicate(match(2, ?, ?, ?)).

% The scrutinee is parsed at the postfix (atom) level rather than as a full
% expression, so it never consumes a `|` -- which would otherwise be
% ambiguous with the arm separator (and with the binary `|` operator).  A
% compound scrutinee is wrapped: `match { a + b } | ...` or `match (t) | ...`.
match(ExpressionFunctor, match_node(Scrutinee, Arms)) -->
  "match",
  separator, % mandatory
  separators,
  postfix(ExpressionFunctor, Scrutinee),
  separators,
  match_arms(ExpressionFunctor, Arms).

match_arms(ExpressionFunctor, [Arm | Arms]) -->
  "|",
  separators,
  match_arm(ExpressionFunctor, Arm),
  match_arms_tail(ExpressionFunctor, Arms).

match_arms_tail(ExpressionFunctor, [Arm | Arms]) -->
  separators,
  "|",
  separators,
  match_arm(ExpressionFunctor, Arm),
  match_arms_tail(ExpressionFunctor, Arms).
match_arms_tail(_, []) --> [].

match_arm(ExpressionFunctor, match_arm([First | Rest], Guard, Result)) -->
  pattern(ExpressionFunctor, First),
  arm_alternatives(ExpressionFunctor, Rest),
  separators,
  match_guard(ExpressionFunctor, Guard),
  "=>",
  separators,
  phrase(ExpressionFunctor, Result).

% Additional `| pattern` alternatives of an or-pattern (before the `=>`).
arm_alternatives(ExpressionFunctor, [Pattern | Patterns]) -->
  separators,
  "|",
  separators,
  pattern(ExpressionFunctor, Pattern),
  arm_alternatives(ExpressionFunctor, Patterns).
arm_alternatives(_, []) --> [].

match_guard(ExpressionFunctor, guard(Expression)) -->
  "if",
  separator, % mandatory
  separators,
  phrase(ExpressionFunctor, Expression),
  separators.
match_guard(_, no_guard) --> [].
