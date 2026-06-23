:- module(postfix, [postfix//2]).

/*  postfix.pl  --  Primary expressions with trailing access / call chains,
    and field assignment.

    This is the "atom" level of the expression grammar.  A primary (literal,
    string, tuple, block, or identifier) may be followed by any chain of:

        .label        member access            foo.bar
        .index        positional access        foo.0
        (args)        call                      foo(1 2)   foo.bar()

    and the whole chain may end in an assignment when its target is an
    access (used to mutate a `mutable` member):

        foo.bar = 3
        foo.0 = 'x'

    Produced AST:

        access_node(Target, Accessor)        Accessor: label(Name) | index(N)
        function_call_node(Target, Arguments)
        assignment_node(AccessNode, Value)

    Calls were previously a separate `function_call` production restricted to
    identifier/block targets; folding them in here lets any primary be
    accessed and called, and lets the two compose (`foo.bar()`).
*/

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(number_literal, [number_literal//1]).
:- use_module(boolean_literal, [boolean_literal//1]).
:- use_module(string_literal, [string_literal//2]).
:- use_module(tuple, [tuple//2]).
:- use_module(block, [block//2]).
:- use_module(identifier, [identifier//1]).
:- use_module(separator, [
  separator//0,
  separators//0
]).

:- meta_predicate(postfix(2, ?, ?, ?)).

postfix(ExpressionFunctor, Node) -->
  primary(ExpressionFunctor, Base),
  postfix_chain(ExpressionFunctor, Base, Accessed),
  optional_assignment(ExpressionFunctor, Accessed, Node).

% The accessible / callable atoms.  (A lambda `function` is parsed at a
% higher level; like the previous grammar, it is not itself a call target.)
primary(_, Node) --> number_literal(Node).
primary(_, Node) --> boolean_literal(Node).
primary(ExpressionFunctor, Node) --> string_literal(ExpressionFunctor, Node).
primary(ExpressionFunctor, Node) --> tuple(ExpressionFunctor, Node).
primary(ExpressionFunctor, Node) --> block(ExpressionFunctor, Node).
primary(_, Node) --> identifier(Node).

% Zero or more `.accessor` or `(arguments)` operations, left-associative.
postfix_chain(ExpressionFunctor, Target, Node) -->
  ".",
  accessor(Accessor),
  postfix_chain(ExpressionFunctor, access_node(Target, Accessor), Node).
postfix_chain(ExpressionFunctor, Target, Node) -->
  separators,
  "(",
  separators,
  call_arguments(ExpressionFunctor, Arguments),
  separators,
  ")",
  postfix_chain(ExpressionFunctor, function_call_node(Target, Arguments), Node).
postfix_chain(_, Target, Target) --> [].

accessor(label(Name)) -->
  identifier(identifier_node(Name)).
accessor(index(Index)) -->
  decimal_digit(First),
  decimal_digits(Rest),
  { number_chars(Index, [First | Rest]) }.

decimal_digits([Digit | Digits]) -->
  decimal_digit(Digit),
  decimal_digits(Digits).
decimal_digits([]) --> [].

decimal_digit(Digit) -->
  [Digit],
  { memberchk(Digit, ['0','1','2','3','4','5','6','7','8','9']) }.

call_arguments(_, []) --> [].
call_arguments(ExpressionFunctor, [Argument | Arguments]) -->
  call_argument(ExpressionFunctor, Argument),
  call_arguments_tail(ExpressionFunctor, Arguments).

call_arguments_tail(_, []) --> [].
call_arguments_tail(ExpressionFunctor, [Argument | Arguments]) -->
  separator, % mandatory
  separators,
  call_argument(ExpressionFunctor, Argument),
  call_arguments_tail(ExpressionFunctor, Arguments).

% An argument is either a placeholder `_` (a hole, turning the call into a
% function awaiting that argument) or an ordinary expression.  `_` is not a
% valid identifier, so the placeholder is unambiguous.
call_argument(_, placeholder_node) -->
  "_".
call_argument(ExpressionFunctor, Argument) -->
  phrase(ExpressionFunctor, Argument).

% An assignment is only formed when the target is a member access, so plain
% identifiers (handled as definitions elsewhere) and call results that are
% not accesses never accidentally parse as assignments.  `=` must not be the
% start of `==`.
optional_assignment(ExpressionFunctor, access_node(Target, Accessor),
                    assignment_node(access_node(Target, Accessor), Value)) -->
  separators,
  assignment_operator,
  separators,
  phrase(ExpressionFunctor, Value).
optional_assignment(_, Node, Node) --> [].

assignment_operator(['=' | Rest], Rest) :-
  Rest \= ['=' | _].
