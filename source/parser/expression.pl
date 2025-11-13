:- module(expression, [expression/3]).

:- use_module(library(dcgs)).

:- use_module(number_literal, [number_literal/3]).
:- use_module(boolean_literal, [boolean_literal/3]).
:- use_module(string_literal, [string_literal/4]).
:- use_module(function, [function/4]).
:- use_module(tuple, [tuple/4]).
:- use_module(function_call, [function_call/4]).
:- use_module(block, [block/4]).
:- use_module(definition, [definition/4]).
:- use_module(conditional, [conditional/4]).
:- use_module(identifier, [identifier/3]).
:- use_module(unary, [unary/4]).
:- use_module(binary, [binary/4,
                       % For some reason this import is needed for base_expression
                       % to find the procedure.
                       failing_binary/4]).

base_expression(BinaryFunctor, Node) -->
  definition(expression, Node)
  | function(expression, Node)
  | phrase(BinaryFunctor, base_expression, Node)
  | number_literal(Node)
  | boolean_literal(Node)
  | string_literal(expression, Node)
  | tuple(expression, Node)
  | function_call(expression, Node)
  | block(expression, Node)
  | conditional(expression, Node)
  | identifier(Node)
  | unary(expression, Node).

expression(Node) -->
  base_expression(binary, Node).
