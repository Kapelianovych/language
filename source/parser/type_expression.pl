:- module(type_expression, [
  type_expression//1,
  type_parameters//1
]).

/*  type_expression.pl  --  Surface syntax for types.

    A *type expression* is what the programmer writes after a `:` in an
    annotation, on the right-hand side of a `type` declaration, or as a
    type-parameter bound.  It is parsed into a syntactic AST that the
    analyser later converts into an internal monotype.

    Grammar (separators are whitespace / comments):

        TypeExpression :- QuantifiedType | ParenthesizedType | TypeReference

        QuantifiedType :- TypeParameters Separator* TypeExpression

            A quantifier prefix introduces a polymorphic type (a `forall`),
            e.g. `<A>(A): A` is `forall A. (A) -> A`.  It is what lets a
            polymorphic type be written in an annotation position -- a
            function parameter or field that is ITSELF polymorphic, which is
            how rank-N types are expressed.  This is distinct from a generic
            type ALIAS (`type Id<A> = (A): A`), whose parameters live on the
            type name and which must be APPLIED (`Id<number>`); a quantified
            type bakes the `forall` in and is used directly.

        ParenthesizedType :-
            "(" Separator* (TypeMember (Separator+ TypeMember)*)?
                (Separator+ "..")?                       -- open-row marker
            Separator* ")"
            (Separator* ":" Separator* TypeExpression)?    -- function return

            A trailing `..` makes the record OPEN ("and possibly more
            fields"); without it the record is closed/exact.  A trailing
            `: ReturnType` instead makes it a FUNCTION type, whose parameter
            types are the (positional) member types.

        TypeMember :- "mutable"? (Identifier ":" Separator* TypeExpression
                                  | TypeExpression)

        TypeReference :- Identifier TypeArguments?

    Produced AST (each node additionally carries a trailing `span(Start, End)`
    of source offsets as its last argument -- see `parser/position.pl`):

        type_name_node(NameCharacters, ArgumentTypeExpressions)
        tuple_type_node(MemberList, Openness)        Openness: open | closed
            member: tuple_type_member(Mutability, Label, TypeExpression)
        function_type_node(ParameterTypeExpressions, ReturnTypeExpression)
        quantified_type_node(TypeParameters, BodyTypeExpression)

    A type-PARAMETER list (`<A b: Bound>`) is parsed by `type_parameters//1`
    into `type_parameter(Name, Bound)` entries, where `Bound` is `no_bound`
    or `bound(TypeExpression)`.  It is shared by `type` declarations and by
    function generics.
*/

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(identifier, [identifier//1, qualified_identifier//2]).
:- use_module(mutability, [mutability//1]).
:- use_module(separator, [
  separator//0,
  separators//0
]).
:- use_module(position, [here//1, span_between/3]).

type_expression(Node) -->
  quantified_type(Node)
  | parenthesized_type(Node)
  | type_reference(Node).

% A quantifier prefix `<A b ..>` turns the following type into a polymorphic
% type (`forall`).  At least one parameter is required (an empty `<>` is not a
% quantifier); `type_parameters//1` only yields a non-empty list when a real
% `<...>` is present, so this never fires on a bare parenthesized/named type.
quantified_type(quantified_type_node(Parameters, Body, Span)) -->
  here(Start),
  type_parameters(Parameters),
  { Parameters = [_ | _] },
  separators,
  type_expression(Body),
  here(End),
  { span_between(Start, End, Span) }.

parenthesized_type(Node) -->
  here(Start),
  "(",
  separators,
  type_members(Members),
  open_marker(Openness),
  separators,
  ")",
  return_suffix(Members, Openness, Start, Node).

% An open-row marker `..` (preceded by a separator when members exist) makes
% the record open.  A name after it (`..R`) CAPTURES the rest as a named row
% variable, so the same `..R` elsewhere refers to the same fields -- this is
% what lets a function preserve a caller's extra fields (open-row results).
% Absent, the record is closed.
open_marker(open(Rest)) -->
  separators,
  "..",
  rest_capture(Rest).
open_marker(closed) --> [].

rest_capture(capture(Name)) -->
  identifier(identifier_node(Name, _)).
rest_capture(anonymous) --> [].

% With a `: ReturnType` suffix this is a function type (parameter types are
% the member types); otherwise a tuple type carrying its openness.  `Start` is
% the position of the opening `(`, threaded in so the produced node's span
% covers the whole parenthesized type (and, for a function type, its return).
return_suffix(Members, _Openness, Start, function_type_node(ParameterTypes, ReturnType, Span)) -->
  separators,
  ":",
  separators,
  type_expression(ReturnType),
  here(End),
  { member_types(Members, ParameterTypes),
    span_between(Start, End, Span)
  }.
return_suffix(Members, Openness, Start, tuple_type_node(Members, Openness, Span)) -->
  here(End),
  { span_between(Start, End, Span) }.

member_types([], []).
member_types([tuple_type_member(_, _, Type, _) | Members], [Type | Types]) :-
  member_types(Members, Types).

type_members([]) --> [].
type_members([Member | Members]) -->
  type_member(Member),
  type_members_tail(Members).

type_members_tail([]) --> [].
type_members_tail([Member | Members]) -->
  separator, % mandatory
  separators,
  type_member(Member),
  type_members_tail(Members).

type_member(tuple_type_member(Mutability, Label, Type, Span)) -->
  here(Start),
  mutability(Mutability),
  (   labeled_type_member(Label, Type)
  |   positional_type_member(Label, Type)
  ),
  here(End),
  { span_between(Start, End, Span) }.

labeled_type_member(labeled(Name), Type) -->
  identifier(identifier_node(Name, _)),
  separators,
  ":",
  separators,
  type_expression(Type).

positional_type_member(positional, Type) -->
  type_expression(Type).

% A named type, optionally applied to angle-bracketed type arguments.  The name
% may be QUALIFIED (`Math.Option`) when it refers to a type brought in by a
% whole-module import; the dotted name is resolved like any other type name.
type_reference(type_name_node(Name, Arguments, Span)) -->
  here(Start),
  qualified_identifier(Name, _),
  type_arguments(Arguments),
  here(End),
  { span_between(Start, End, Span) }.

type_arguments(Arguments) -->
  "<",
  separators,
  type_argument(First),
  type_argument_list_tail(Rest),
  separators,
  ">",
  { Arguments = [First | Rest] }.
type_arguments([]) --> [].

type_argument_list_tail([]) --> [].
type_argument_list_tail([Next | Rest]) -->
  separator, % mandatory
  separators,
  type_argument(Next),
  type_argument_list_tail(Rest).

% A type argument is either a HOLE `_` (a PLACEHOLDER for partial type
% application, e.g. `Either<_ string>`) or a type expression.  A reference
% with holes, or with fewer arguments than the constructor's arity (e.g.
% `Either<number>`), denotes a SECTION -- a type-level function awaiting the
% remaining arguments.  `_` is not a valid identifier (it is not XID_Start),
% so it is unambiguous here.
type_argument(type_hole(Span)) -->
  here(Start), "_", here(End), { span_between(Start, End, Span) }.
type_argument(Argument) -->
  type_expression(Argument).

% ---------------------------------------------------------------------------
% Type-parameter lists (declarations and function generics)
% ---------------------------------------------------------------------------

% `<A b: Bound c>` or nothing.
type_parameters([First | Rest]) -->
  "<",
  separators,
  type_parameter(First),
  type_parameters_tail(Rest),
  separators,
  ">".
type_parameters([]) --> [].

type_parameters_tail([]) --> [].
type_parameters_tail([Next | Rest]) -->
  separator, % mandatory
  separators,
  type_parameter(Next),
  type_parameters_tail(Rest).

% A type parameter is `Name` (kind `*`), `Name: Bound` (kind `*`, bounded),
% or `Name<_ ... _>` (HIGHER-KINDED: the number of `_` holes is its arity, so
% `F<_>` has kind `* -> *`).  A higher-kinded parameter takes no bound.
type_parameter(type_parameter(Name, Kind, Bound, Span)) -->
  here(Start),
  identifier(identifier_node(Name, _)),
  parameter_kind_and_bound(Kind, Bound),
  here(End),
  { span_between(Start, End, Span) }.

parameter_kind_and_bound(Kind, no_bound) -->
  "<",
  separators,
  kind_holes(Kind),
  separators,
  ">".
parameter_kind_and_bound(0, Bound) -->
  type_parameter_bound(Bound).

kind_holes(Count) -->
  "_",
  kind_holes_tail(Rest),
  { Count is Rest + 1 }.

kind_holes_tail(Count) -->
  separator, % mandatory
  separators,
  "_",
  kind_holes_tail(Rest),
  { Count is Rest + 1 }.
kind_holes_tail(0) --> [].

type_parameter_bound(bound(TypeExpression)) -->
  separators,
  ":",
  separators,
  type_expression(TypeExpression).
type_parameter_bound(no_bound) --> [].
