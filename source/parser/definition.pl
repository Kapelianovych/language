:- module(definition, [definition//2]).

/*  definition.pl  --  `name = value` bindings, with an optional type
    annotation:

        Definition :- Identifier (":" Separator* TypeExpression Separator*)?
                      Separator* "=" Separator* Expression

    Examples:

        foo = 1
        foo: number = 1

    The produced node carries the annotation explicitly:

        definition_node(Target, TypeAnnotation, Value)

    where `TypeAnnotation` is either `no_annotation` or
    `type_annotation(TypeExpression)`.
*/

:- use_module(library(dcgs)).
:- use_module(separator, [separators//0]).
:- use_module(identifier, [identifier//1]).
:- use_module(type_annotation, [type_annotation//1]).

:- meta_predicate(definition(2, ?, ?, ?)).

definition(
  ExpressionFunctor,
  definition_node(
    AssignmentTarget,
    TypeAnnotation,
    Value
  )
) -->
  identifier(AssignmentTarget),
  type_annotation(TypeAnnotation),
  separators,
  "=",
  separators,
  phrase(ExpressionFunctor, Value).
