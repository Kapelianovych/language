:- module(boolean_literal, [boolean_literal/3]).

:- use_module(library(dcgs)).

boolean_literal(boolean_node(true)) --> "true".
boolean_literal(boolean_node(false)) --> "false".
