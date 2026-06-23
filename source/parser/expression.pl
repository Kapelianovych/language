:- module(expression, [expression//1]).

:- use_module(library(dcgs)).
:- use_module(function, [function//2]).
:- use_module(definition, [definition//2]).
:- use_module(destructuring, [destructuring//2]).
:- use_module(type_declaration, [type_declaration//1]).
:- use_module(conditional, [conditional//2]).
:- use_module(match, [match//2]).
:- use_module(unary, [unary//2]).
:- use_module(postfix, [postfix//2]).
:- use_module(binary, [
  binary//2,
  % For some reason this import is needed for base_expression
  % to find the procedure.
  failing_binary//2
]).

base_expression(BinaryFunctor, Node) -->
  type_declaration(Node)
  | definition(expression, Node)
  | destructuring(expression, Node)
  | function(expression, Node)
  % `conditional` and `match` are tried before `binary` so their bodies /
  % arm results extend greedily: `match s | _ => w + h` keeps `w + h` in the
  % arm rather than parsing as `(match ...) + h`.  (Both still start with a
  % keyword, so they don't interfere with binary expressions.)
  | conditional(expression, Node)
  | match(expression, Node)
  | phrase(BinaryFunctor, base_expression, Node)
  | unary(expression, Node)
  % `postfix` is the atom level: literals, strings, tuples, blocks and
  % identifiers, plus any trailing `.access` / `(call)` / `= assignment`.
  | postfix(expression, Node).

expression(Node) -->
  base_expression(binary, Node).
