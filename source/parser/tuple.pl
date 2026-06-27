:- module(tuple, [tuple//2]).

/*  tuple.pl  --  Tuples with positional and labeled members.

    A tuple mixes positional and labeled members, each optionally `mutable`
    (members are readonly by default):

        ()                                    the unit value
        (1 2 3)                               three positional members
        (one: number = 1  'x'  two = true)    labeled + positional, mixed
        (mutable count: number = 0)           a mutable labeled member

    Labeled members reuse the `name (: Type)? = value` shape; their order is
    irrelevant.  Positional members are bare expressions and their relative
    order is significant.

    Produced AST (each node additionally carries a trailing `span(Start, End)`
    of source offsets as its last argument -- see `parser/position.pl`):

        tuple_node(Members)

    where each member is

        tuple_member(Mutability, Label, TypeAnnotation, Value)

    with `Mutability` in {readonly, mutable}, `Label` either `positional`
    or `labeled(NameCharacters)`, and `TypeAnnotation` either `no_annotation`
    or `type_annotation(TypeExpression)` (always `no_annotation` for
    positional members).
*/

:- use_module(library(dcgs)).
:- use_module(identifier, [identifier//1]).
:- use_module(mutability, [mutability//1]).
:- use_module(type_annotation, [type_annotation//1]).
:- use_module(separator, [
  separator//0,
  separators//0
]).
:- use_module(position, [here//1, span_between/3]).

:- meta_predicate(tuple(2, ?, ?, ?)).

tuple(ExpressionFunctor, tuple_node(Members, Span)) -->
  here(Start),
  "(",
  separators,
  tuple_members(ExpressionFunctor, Members),
  separators,
  ")",
  here(End),
  { span_between(Start, End, Span) }.

tuple_members(_, []) --> [].
tuple_members(ExpressionFunctor, [Member | Members]) -->
  tuple_member(ExpressionFunctor, Member),
  tuple_members_tail(ExpressionFunctor, Members).

tuple_members_tail(_, []) --> [].
tuple_members_tail(ExpressionFunctor, [Member | Members]) -->
  separator, % mandatory
  separators,
  tuple_member(ExpressionFunctor, Member),
  tuple_members_tail(ExpressionFunctor, Members).

% A member is either a SPREAD (`..expr`, splicing another record's fields in)
% or an optional `mutable` followed by a labeled or positional body.  Spread
% is tried first: no expression begins with `..`, so it is unambiguous.
tuple_member(ExpressionFunctor, Member) -->
  spread_member(ExpressionFunctor, Member)
  | plain_member(ExpressionFunctor, Member).

spread_member(ExpressionFunctor, spread_member(Value, Span)) -->
  here(Start),
  "..",
  phrase(ExpressionFunctor, Value),
  here(End),
  { span_between(Start, End, Span) }.

% Labeled is tried first: it only commits once it has seen the `=`.
plain_member(ExpressionFunctor, tuple_member(Mutability, Label, TypeAnnotation, Value, Span)) -->
  here(Start),
  mutability(Mutability),
  (   labeled_member(ExpressionFunctor, Label, TypeAnnotation, Value)
  |   positional_member(ExpressionFunctor, Label, TypeAnnotation, Value)
  ),
  here(End),
  { span_between(Start, End, Span) }.

labeled_member(ExpressionFunctor, labeled(Name), TypeAnnotation, Value) -->
  identifier(identifier_node(Name, _)),
  type_annotation(TypeAnnotation),
  separators,
  "=",
  separators,
  phrase(ExpressionFunctor, Value).

positional_member(ExpressionFunctor, positional, no_annotation, Value) -->
  phrase(ExpressionFunctor, Value).
