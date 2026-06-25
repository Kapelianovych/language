:- module(program, [program//1]).

/*  program.pl  --  Top-level program structure, including the module system.

    A program is a separator-separated sequence of *items*.  An item is one of:

        use_node(Path, Names)
            an IMPORT.  `use ./math:(add Option Some)` brings the listed
            names from another module into scope.  `Path` is the relative path characters
            (without the `.sl` extension), `Names` a list of imported name
            character-lists.  Imports resolve uniformly across all three
            namespaces (values, types, constructors): each name is bound to
            whatever it is in the source module's exported interface.

        public_node(Item)
            an EXPORT.  `public` prefixes a definition, `type` declaration, or
            `external` to expose it to importers; everything else is
            module-private.  Exporting a tagged-union type exports its
            constructors too; exporting an `external` lets a foreign binding be
            declared once and imported elsewhere.

        external_node(Name, Type, Source)
            a FOREIGN (JavaScript) IMPORT.  `external` binds a name to a piece
            of JavaScript, ascribing it a type that the compiler trusts (the
            one unsafe point of the JS boundary).  `Source` is one of:
                js_global                  `external max : T` an ambient global
                                           of the same name (no source clause)
                js_expression(Js)          `= 'Math.max'`     a JS expression
                js_module(Module, default) `from "lodash"`    import, same name
                js_module(Module, Foreign) `= 'print' from './x.js'`  renamed
            The foreign strings are single-quoted but, unlike the language's
            own strings, carry no escapes or interpolation -- they are raw
            fragments, any character except the closing `'`.
            `Type` is an ordinary type expression; if it is a function type,
            the back end wraps the call in a currying shim (the JS side is
            uncurried, the language side curried).  All values cross the
            boundary AS-IS -- tuples and variants included -- with no
            representation conversion.

        any other expression (definition, type declaration, bare expression)
            an ordinary, module-private top-level item.

    `use`, `public` and `external` are soft keywords: they only take on their
    special meaning when followed by the rest of an import / export / foreign
    import; a bare identifier `use`, `public` or `external` (not so followed)
    still parses normally, because each rule requires a mandatory separator and
    the expected shape, and the parser backtracks to `expression` otherwise.
*/

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(separator, [
  separator//0,
  separators//0
]).
:- use_module(identifier, [identifier//1]).
:- use_module(expression, [expression//1]).
:- use_module(type_expression, [type_expression//1]).
:- use_module(whitespace, [is_whitespace/1]).

program(program_node(Items)) -->
  separators,
  program_tail(Items).

program_tail([]) --> [].
program_tail([Item | Items]) -->
  program_item(Item),
  separators,
  program_tail(Items).

% An import and an export each lead with their soft keyword; anything else is
% an ordinary expression.  The alternation backtracks, so `use`/`public` used
% as plain identifiers fall through to `expression`.
program_item(Item) -->
  use_declaration(Item)
  | public_item(Item)
  | external_declaration(Item)
  | expression(Item).

% ---------------------------------------------------------------------------
% Imports:  use ./path:(a b c)
% ---------------------------------------------------------------------------

use_declaration(use_node(Path, Names)) -->
  "use",
  separator, % mandatory: separates the keyword from the path
  separators,
  import_path(Path),
  separators,
  ":",
  separators,
  import_names(Names).

% A relative path is a maximal run of path characters (everything up to the
% `:` separator or surrounding whitespace).  It carries no `.sl` extension.
import_path([Character | Characters]) -->
  path_character(Character),
  import_path_tail(Characters).

import_path_tail([Character | Characters]) -->
  path_character(Character),
  import_path_tail(Characters).
import_path_tail([]) --> [].

path_character(Character) -->
  [Character],
  { \+ member(Character, [':', '(', ')'])
  , \+ is_whitespace(Character)
  }.

% A parenthesised list of names.
import_names(Names) -->
  "(",
  separators,
  identifier(identifier_node(First)),
  import_names_tail(Rest),
  separators,
  ")",
  { Names = [First | Rest] }.

import_names_tail([Name | Rest]) -->
  separator, % mandatory
  separators,
  identifier(identifier_node(Name)),
  import_names_tail(Rest).
import_names_tail([]) --> [].

% ---------------------------------------------------------------------------
% Exports:  public <definition | type declaration>
% ---------------------------------------------------------------------------

% `public` may prefix an ordinary definition / type declaration OR an
% `external` (so a foreign binding can be declared once and re-imported).
public_item(public_node(Item)) -->
  "public",
  separator, % mandatory
  separators,
  ( external_declaration(Item)
  | expression(Item)
  ).

% ---------------------------------------------------------------------------
% Foreign imports:
%     external NAME : TYPE
%     external NAME : TYPE = "jsExpression"
%     external NAME : TYPE from "module"
%     external NAME : TYPE = "foreignName" from "module"
% ---------------------------------------------------------------------------

external_declaration(external_node(Name, Type, Source)) -->
  "external",
  separator, % mandatory: separates the keyword from the name
  separators,
  identifier(identifier_node(Name)),
  separators,
  ":",
  separators,
  type_expression(Type),
  separators,
  external_source(Source).

% Order matters: the combined `= 'name' from 'module'` form is tried before
% the bare `= 'expr'` form, so the trailing `from` is not left dangling; the
% sourceless `js_global` form (an ambient global of the same name) is tried
% last, so it only applies when there is no `=` clause to consume.
external_source(js_module(Module, named(Foreign))) -->
  "=",
  separators,
  js_string(Foreign),
  separators,
  "from",
  separators,
  js_string(Module).
external_source(js_expression(Js)) -->
  "=",
  separators,
  js_string(Js).
external_source(js_module(Module, default)) -->
  "from",
  separators,
  js_string(Module).
external_source(js_global) --> [].

% A single-quoted JavaScript fragment (a name, member path, or module
% specifier).  Unlike the language's own strings it is raw: no escapes and no
% interpolation -- any character except the closing `'`.
js_string(Characters) -->
  "'",
  js_string_characters(Characters),
  "'".

js_string_characters([Character | Characters]) -->
  [Character],
  { Character \== '\'' },
  js_string_characters(Characters).
js_string_characters([]) --> [].
