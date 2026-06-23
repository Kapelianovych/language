:- module(type_annotation, [type_annotation//1]).

/*  type_annotation.pl  --  The optional `: TypeExpression` suffix shared by
    definitions, function parameters and function return positions.

    Produces either

        no_annotation
        type_annotation(TypeExpression)

    A leading run of separators before the `:` is allowed so the colon may
    be written tight (`a: string`) or spaced.
*/

:- use_module(library(dcgs)).
:- use_module(separator, [separators//0]).
:- use_module(type_expression, [type_expression//1]).

type_annotation(type_annotation(TypeExpression)) -->
  separators,
  ":",
  separators,
  type_expression(TypeExpression).
type_annotation(no_annotation) --> [].
