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

        TypeExpression :- ParenthesizedType | TypeReference

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

    Produced AST:

        type_name_node(NameCharacters, ArgumentTypeExpressions)
        tuple_type_node(MemberList, Openness)        Openness: open | closed
            member: tuple_type_member(Mutability, Label, TypeExpression)
        function_type_node(ParameterTypeExpressions, ReturnTypeExpression)

    A type-PARAMETER list (`<A b: Bound>`) is parsed by `type_parameters//1`
    into `type_parameter(Name, Bound)` entries, where `Bound` is `no_bound`
    or `bound(TypeExpression)`.  It is shared by `type` declarations and by
    function generics.
*/

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(identifier, [identifier//1]).
:- use_module(mutability, [mutability//1]).
:- use_module(separator, [
  separator//0,
  separators//0
]).

type_expression(Node) -->
  parenthesized_type(Node)
  | type_reference(Node).

parenthesized_type(Node) -->
  "(",
  separators,
  type_members(Members),
  open_marker(Openness),
  separators,
  ")",
  return_suffix(Members, Openness, Node).

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
  identifier(identifier_node(Name)).
rest_capture(anonymous) --> [].

% With a `: ReturnType` suffix this is a function type (parameter types are
% the member types); otherwise a tuple type carrying its openness.
return_suffix(Members, _Openness, function_type_node(ParameterTypes, ReturnType)) -->
  separators,
  ":",
  separators,
  type_expression(ReturnType),
  { member_types(Members, ParameterTypes) }.
return_suffix(Members, Openness, tuple_type_node(Members, Openness)) --> [].

member_types([], []).
member_types([tuple_type_member(_, _, Type) | Members], [Type | Types]) :-
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

type_member(tuple_type_member(Mutability, Label, Type)) -->
  mutability(Mutability),
  (   labeled_type_member(Label, Type)
  |   positional_type_member(Label, Type)
  ).

labeled_type_member(labeled(Name), Type) -->
  identifier(identifier_node(Name)),
  separators,
  ":",
  separators,
  type_expression(Type).

positional_type_member(positional, Type) -->
  type_expression(Type).

% A named type, optionally applied to angle-bracketed type arguments.
type_reference(type_name_node(Name, Arguments)) -->
  identifier(identifier_node(Name)),
  type_arguments(Arguments).

type_arguments(Arguments) -->
  "<",
  separators,
  type_expression(First),
  type_argument_list_tail(Rest),
  separators,
  ">",
  { Arguments = [First | Rest] }.
type_arguments([]) --> [].

type_argument_list_tail([]) --> [].
type_argument_list_tail([Next | Rest]) -->
  separator, % mandatory
  separators,
  type_expression(Next),
  type_argument_list_tail(Rest).

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

type_parameter(type_parameter(Name, Bound)) -->
  identifier(identifier_node(Name)),
  type_parameter_bound(Bound).

type_parameter_bound(bound(TypeExpression)) -->
  separators,
  ":",
  separators,
  type_expression(TypeExpression).
type_parameter_bound(no_bound) --> [].
