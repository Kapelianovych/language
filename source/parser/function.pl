:- module(function, [function//2]).

/*  function.pl  --  Anonymous functions, with optional type annotations on
    each parameter and on the return position:

        Function :-
            "(" Separator*
                (Parameter (Separator+ Parameter)*)?
            Separator* ")"
            (":" Separator* TypeExpression)?
            Separator* Expression

        Parameter :- Identifier (":" Separator* TypeExpression)?

    A function may be preceded by a list of (optionally bounded) type
    parameters, giving explicit generics:

        (x) x
        (a: string): string a
        <A>(x: A): A x
        <A: (x: string ..)>(t: A): string t.x

    Produced AST (each node additionally carries a trailing `span(Start, End)`
    of source offsets as its last argument -- see `parser/position.pl`):

        function_node(TypeParameters, Parameters, ReturnAnnotation, Body)

    where `TypeParameters` is a (possibly empty) list of
    `type_parameter(Name, Bound)`, each parameter is

        parameter_node(identifier_node(Name), TypeAnnotation)

    and `ReturnAnnotation` / each `TypeAnnotation` is `no_annotation` or
    `type_annotation(TypeExpression)`.
*/

:- use_module(library(dcgs)).
:- use_module(pattern, [irrefutable_pattern//2]).
:- use_module(type_annotation, [type_annotation//1]).
:- use_module(type_expression, [type_parameters//1]).
:- use_module(separator, [
  separator//0,
  separators//0
]).
:- use_module(position, [here//1, span_between/3]).

:- meta_predicate(function(2, ?, ?, ?)).

function(ExpressionFunctor, function_node(TypeParameters, Parameters, ReturnAnnotation, Body, Span)) -->
  here(Start),
  type_parameters(TypeParameters),
  separators,
  "(",
  separators,
  function_parameters(ExpressionFunctor, Parameters),
  separators,
  ")",
  type_annotation(ReturnAnnotation),
  separators,
  phrase(ExpressionFunctor, Body),
  here(End),
  { span_between(Start, End, Span) }.

function_parameters(_, []) --> [].
function_parameters(ExpressionFunctor, [Parameter | Parameters]) -->
  function_parameter(ExpressionFunctor, Parameter),
  function_parameters_tail(ExpressionFunctor, Parameters).

% A parameter is a pattern (commonly just an identifier, but also a record
% pattern for destructuring) with an optional type annotation.
function_parameter(ExpressionFunctor, parameter_node(Pattern, TypeAnnotation, Span)) -->
  here(Start),
  irrefutable_pattern(ExpressionFunctor, Pattern),
  type_annotation(TypeAnnotation),
  here(End),
  { span_between(Start, End, Span) }.

function_parameters_tail(_, []) --> [].
function_parameters_tail(ExpressionFunctor, [Parameter | Parameters]) -->
  separator, % mandatory
  separators,
  function_parameter(ExpressionFunctor, Parameter),
  function_parameters_tail(ExpressionFunctor, Parameters).
