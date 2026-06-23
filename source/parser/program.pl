:- module(program, [program//1]).

/*  program.pl  --  Top-level program structure, including the module system.

    A program is a separator-separated sequence of *items*.  An item is one of:

        use_node(Path, Names)
            an IMPORT.  `use ./math:(add Option Some)` brings the listed
            names from another module into scope; `use ./math:add` is the
            one-name shorthand.  `Path` is the relative path characters
            (without the `.sl` extension), `Names` a list of imported name
            character-lists.  Imports resolve uniformly across all three
            namespaces (values, types, constructors): each name is bound to
            whatever it is in the source module's exported interface.

        public_node(Item)
            an EXPORT.  `public` prefixes a definition or `type` declaration
            to expose it to importers; everything else is module-private.
            Exporting a tagged-union type exports its constructors too.

        any other expression (definition, type declaration, bare expression)
            an ordinary, module-private top-level item.

    `use` and `public` are soft keywords: they only take on their special
    meaning when followed by the rest of an import / export; a bare
    identifier `use` or `public` (not so followed) still parses normally,
    because both rules require a mandatory separator and the import/export
    shape, and the parser backtracks to `expression` otherwise.
*/

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(separator, [
  separator//0,
  separators//0
]).
:- use_module(identifier, [identifier//1]).
:- use_module(expression, [expression//1]).

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
  | expression(Item).

% ---------------------------------------------------------------------------
% Imports:  use ./path:(a b c)   or   use ./path:name
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
  { \+ member(Character, [':', ' ', '\t', '\n', '\r', '(', ')']) }.

% Either a parenthesised list of names or a single bare name.
import_names(Names) -->
  "(",
  separators,
  identifier(identifier_node(First)),
  import_names_tail(Rest),
  separators,
  ")",
  { Names = [First | Rest] }.
import_names([Name]) -->
  identifier(identifier_node(Name)).

import_names_tail([Name | Rest]) -->
  separator, % mandatory
  separators,
  identifier(identifier_node(Name)),
  import_names_tail(Rest).
import_names_tail([]) --> [].

% ---------------------------------------------------------------------------
% Exports:  public <definition | type declaration>
% ---------------------------------------------------------------------------

public_item(public_node(Item)) -->
  "public",
  separator, % mandatory
  separators,
  expression(Item).
