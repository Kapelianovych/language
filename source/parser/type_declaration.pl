:- module(type_declaration, [type_declaration//1]).

/*  type_declaration.pl  --  `type` declarations.

    A declaration introduces a named type, which is one of:

      * a TAGGED UNION (variant / sum type) -- a `|`-separated list of
        constructors, each with zero or more positional field types:

            type Shape = Circle(number) | Rect(number number)
            type Option<A> = Some(A) | None
            type Color = Red | Green | Blue
            type Wrap = Wrap(number)            -- single constructor (parens)
            type Unit = | Unit                  -- single nullary (leading |)

      * a STRUCTURAL alias for a type expression (default), or a NOMINAL one
        when the body is prefixed with `opaque`:

            type UserId = number                -- structural
            type UserId = opaque number          -- nominal

    Produced AST (each node -- including each `constructor(...)` -- additionally
    carries a trailing `span(Start, End)` of source offsets as its last argument;
    see `parser/position.pl`):

        type_declaration_node(NameChars, ParameterList, Opacity, Body)

    where for a variant `Opacity` is `variant` and `Body` is
    `variant_body([constructor(CtorName, FieldTypeExpressions), ...])`;
    otherwise `Opacity` is `opaque`/`transparent` and `Body` is a type
    expression.

    Variant detection (vs a bare alias like `type Id = number`): a body is a
    variant when it has a leading `|`, two or more constructors, or a single
    constructor written with a field list `Name(...)`.
*/

:- use_module(library(dcgs)).
:- use_module(identifier, [identifier//1]).
:- use_module(separator, [
  separator//0,
  separators//0
]).
:- use_module(type_expression, [
  type_expression//1,
  type_parameters//1
]).
:- use_module(position, [here//1, span_between/3]).

type_declaration(type_declaration_node(Name, Parameters, Opacity, Body, Span)) -->
  here(Start),
  "type",
  separator, % mandatory
  separators,
  identifier(identifier_node(Name, _)),
  type_parameters(Parameters),
  separators,
  "=",
  separators,
  declaration_body(Opacity, Body),
  here(End),
  { span_between(Start, End, Span) }.

declaration_body(variant, variant_body(Constructors)) -->
  variant_body_form(Constructors).
declaration_body(Opacity, Body) -->
  opacity(Opacity),
  type_expression(Body).

opacity(opaque) -->
  "opaque",
  separator, % mandatory
  separators.
opacity(transparent) --> [].

% The three variant-like shapes (see header).
variant_body_form(Constructors) -->
  "|",
  separators,
  constructor_list(Constructors).
variant_body_form(Constructors) -->
  constructor_list(Constructors),
  { Constructors = [_, _ | _] }.
variant_body_form([Constructor]) -->
  constructor_declaration(Constructor),
  { Constructor = constructor(_, [_ | _], _) }.

constructor_list([Constructor | Constructors]) -->
  constructor_declaration(Constructor),
  constructor_list_tail(Constructors).

constructor_list_tail([Constructor | Constructors]) -->
  separators,
  "|",
  separators,
  constructor_declaration(Constructor),
  constructor_list_tail(Constructors).
constructor_list_tail([]) --> [].

constructor_declaration(constructor(Name, FieldTypes, Span)) -->
  here(Start),
  identifier(identifier_node(Name, _)),
  constructor_fields(FieldTypes),
  here(End),
  { span_between(Start, End, Span) }.

constructor_fields(FieldTypes) -->
  "(",
  separators,
  field_type_list(FieldTypes),
  separators,
  ")".
constructor_fields([]) --> [].

field_type_list([Type | Types]) -->
  type_expression(Type),
  field_type_list_tail(Types).
field_type_list([]) --> [].

field_type_list_tail([Type | Types]) -->
  separator, % mandatory
  separators,
  type_expression(Type),
  field_type_list_tail(Types).
field_type_list_tail([]) --> [].
