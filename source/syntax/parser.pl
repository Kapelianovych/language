:- module(parser, [parse_tokens/3, green_text/2]).

/*  source/syntax/parser.pl  --  Recovering recursive-descent parser.
    ========================================================================

    Consumes the lossless token list from `lexer:tokenize/2` and produces a
    GREEN TREE (lossless concrete syntax tree) plus a DIAGNOSTICS list.

    See the lexer for the lossless-token contract.  This file adds:

      * ERROR RECOVERY -- the parser never fails and never hangs.  When it
        cannot parse what it expects it emits an `error` node and/or a
        zero-width `missing` leaf, records a diagnostic, and carries on.  Every
        path consumes a token or stops at a real boundary, so it terminates.

      * LOSSLESSNESS -- trivia (whitespace/comments) are attached as leaves and
        `missing` leaves have empty text, so the in-order concatenation of all
        leaves reproduces the source exactly (`green_text/2`, checked in tests).

    GREEN TREE SHAPE
        node(Kind, Children)        -- internal node
        t(Kind, Text, Start, End)   -- a lexer token reused verbatim (leaf)
        t(missing, [], P, P)        -- a required-but-absent token (zero width)

    SOFT KEYWORDS
        `use`, `public`, `external`, `module`, `type`, `if`, `else`, `match`,
        `mutable`, `readonly` all lex as ordinary `ident` tokens, so they are
        recognised by their TEXT (`keyword/2`) at the positions where they take
        on meaning, and otherwise parse as plain identifiers.

    EXPRESSIONS use precedence climbing (Pratt) with the operator table copied
    from `source/parser/binary.pl`, plus `=` (definitions) at the lowest
    precedence.  This is deterministic -- no ambiguity-by-backtracking, no hang.

    SCRYER NOTE
        A quoted operator atom as an operand of `==`/`=`/`\=` trips the reader
        (`incomplete_reduction`).  So punctuation token kinds that are also
        operators (`:`  `|`  `->`  `=`) are compared through the `punct/2` FACTS
        (operator atoms are safe in argument position), never with `== '...'`.
*/

% "use" etc. read as char lists so they compare equal to lexer token text.
:- set_prolog_flag(double_quotes, chars).

:- use_module(library(lists)).

% ===========================================================================
% Token cursor.
% ===========================================================================

trivia_kind(whitespace).
trivia_kind(comment).

% Punctuation/operator token kinds, named so they can be tested without writing
% `== ':'` etc. (which the Scryer reader rejects -- see header note).
punct(dot,         '.').
punct(open_paren,  '(').
punct(close_paren, ')').
punct(open_brace,  '{').
punct(close_brace, '}').
punct(colon,       ':').
punct(bar,         '|').
punct(arrow,       '=>').
punct(eq,          '=').
punct(at,          '@').    % macro invocation
punct(backtick,    '`').    % quasiquote
punct(tilde,       '~').    % unquote
punct(open_angle,  '<').    % type parameters / arguments
punct(close_angle, '>').    % (`<`/`>` also lex as comparison operators)

skip_trivia([t(K, Tx, S, E) | Ts], [t(K, Tx, S, E) | Trivia], Rest) :-
  trivia_kind(K), !,
  skip_trivia(Ts, Trivia, Rest).
skip_trivia(Tokens, [], Tokens).

% peek(+Tokens, -Kind): kind of the next significant token.
peek(Tokens, Kind) :-
  skip_trivia(Tokens, _, [t(Kind, _, _, _) | _]).

% peek_punct(+Tokens, +Name): the next significant token is the named punctuation.
peek_punct(Tokens, Name) :-
  peek(Tokens, Kind),
  punct(Name, Kind).

% keyword(+Tokens, +Word): next significant token is an `ident` with text Word.
keyword(Tokens, Word) :-
  skip_trivia(Tokens, _, [t(ident, Text, _, _) | _]),
  Text == Word.

% offset of the next significant token (for placing zero-width markers).
offset(Tokens, Offset) :-
  skip_trivia(Tokens, _, [t(_, _, Offset, _) | _]).

% bump(+Tokens, -Rest, -Children): consume leading trivia + one significant token.
bump(Tokens, Rest, Children) :-
  skip_trivia(Tokens, Trivia, [Significant | Rest]),
  append(Trivia, [Significant], Children).

% expect_punct(+Name, +Tokens, -Rest, -Children, +D0, -D): consume the named
% punctuation, or emit a zero-width `missing` leaf + diagnostic without consuming.
expect_punct(Name, Tokens, Rest, Children, D0, D) :-
  ( peek_punct(Tokens, Name) ->
      bump(Tokens, Rest, Children), D0 = D
  ; punct(Name, Kind),
    missing(Tokens, Kind, Children, D0, D),
    Rest = Tokens
  ).

% expect_kind(+Kind, ...): same, for a non-punctuation token kind (e.g. ident).
expect_kind(Kind, Tokens, Rest, Children, D0, D) :-
  ( peek(Tokens, Kind) ->
      bump(Tokens, Rest, Children), D0 = D
  ; missing(Tokens, Kind, Children, D0, D),
    Rest = Tokens
  ).

missing(Tokens, What, [t(missing, [], At, At)], [diagnostic(At, At, expected(What)) | D], D) :-
  offset(Tokens, At).

% ===========================================================================
% Program / items.
%
% An item is a keyword form (use / public / external / type / module) or an
% expression (definitions are `name = expr`, handled by the `=` operator).
% ===========================================================================

%% parse_tokens(+Tokens, -GreenTree, -Diagnostics).
parse_tokens(Tokens, node(program, Children), Diagnostics) :-
  items(Tokens, Rest, ItemChildren, Diagnostics, []),
  skip_trivia(Rest, Trivia, [Eof | _]),
  append(ItemChildren, Trivia, WithTrivia),
  append(WithTrivia, [Eof], Children).

items(Tokens, Tokens, [], D, D) :-
  peek(Tokens, eof), !.
items(Tokens, Rest, [Item | Items], D0, D) :-
  item(Tokens, Tokens1, Item, D0, D1), !,
  items(Tokens1, Rest, Items, D1, D).
items(Tokens, Rest, [node(error, ErrorChildren) | Items], D0, D) :-
  % Nothing starts an item here: consume one token as error and recover.
  offset(Tokens, At),
  bump(Tokens, Tokens1, ErrorChildren),
  items(Tokens1, Rest, Items, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

% A single item.  Keyword forms are tried before generic expressions because
% the keywords also lex as identifiers (which start expressions).
item(Tokens, Rest, Node, D0, D) :- keyword(Tokens, "use"),      !, use_declaration(Tokens, Rest, Node, D0, D).
item(Tokens, Rest, Node, D0, D) :- keyword(Tokens, "public"),   !, public_item(Tokens, Rest, Node, D0, D).
item(Tokens, Rest, Node, D0, D) :- keyword(Tokens, "external"), !, external_declaration(Tokens, Rest, Node, D0, D).
item(Tokens, Rest, Node, D0, D) :- keyword(Tokens, "type"),     !, type_declaration(Tokens, Rest, Node, D0, D).
item(Tokens, Rest, Node, D0, D) :- keyword(Tokens, "module"),   !, module_declaration(Tokens, Rest, Node, D0, D).
item(Tokens, Rest, Node, D0, D) :- keyword(Tokens, "macro"),    !, macro_declaration(Tokens, Rest, Node, D0, D).
item(Tokens, Rest, Node, D0, D) :-
  peek(Tokens, Kind), starts_expression(Tokens, Kind),
  expression(0, Tokens, Rest, Node, D0, D).

% starts_expression: can an expression begin with the next token?  (Keyword
% items are handled earlier, so a leading keyword-ident does not reach here in
% item position; inside expressions, `if`/`match` are dispatched in atom_expression.)
starts_expression(_, number).
starts_expression(_, string).
starts_expression(_, ident).
starts_expression(_, underscore).                      % `_` placeholder
starts_expression(_, Kind) :- punct(open_paren, Kind).
starts_expression(_, Kind) :- punct(open_brace, Kind).
starts_expression(_, Kind) :- punct(at, Kind).         % @macro(..)
starts_expression(_, Kind) :- punct(backtick, Kind).   % `(..) quasiquote
starts_expression(_, Kind) :- punct(tilde, Kind).      % ~x unquote
starts_expression(_, Kind) :- unary_operator(Kind).

% ===========================================================================
% Imports:  use PATH            (whole module)
%           use PATH:(a b c)    (named)
% A PATH (e.g. `./math`, `Compiler`) is a run of NON-trivia tokens with no
% spaces, ending before a space or `:`.
% ===========================================================================

use_declaration(Tokens, Rest, node(use, Children), D0, D) :-
  bump(Tokens, Tokens1, UseChildren),             % `use`
  path(Tokens1, Tokens2, PathChildren),
  use_tail(Tokens2, Rest, TailChildren, D0, D),
  append(UseChildren, PathChildren, C1),
  append(C1, TailChildren, Children).

use_tail(Tokens, Rest, Children, D0, D) :-
  ( peek_punct(Tokens, colon) ->
      bump(Tokens, Tokens1, ColonChildren),
      import_names(Tokens1, Rest, NamesChildren, D0, D),
      append(ColonChildren, NamesChildren, Children)
  ; Children = [], Rest = Tokens, D0 = D ).

% The path: leading trivia, then the maximal run of contiguous significant
% tokens that are neither `:` nor end-of-input.
path(Tokens, Rest, Children) :-
  skip_trivia(Tokens, Trivia, Tokens1),
  path_tokens(Tokens1, Rest, PathTokens),
  append(Trivia, PathTokens, Children).

path_tokens([t(K, Tx, S, E) | Ts], Rest, [t(K, Tx, S, E) | More]) :-
  \+ trivia_kind(K), \+ punct(colon, K), K \== eof, !,
  path_tokens(Ts, Rest, More).
path_tokens(Rest, Rest, []).

import_names(Tokens, Rest, Children, D0, D) :-
  expect_punct(open_paren, Tokens, Tokens1, OpenChildren, D0, D1),
  name_list(Tokens1, Tokens2, NameChildren, D1, D2),
  expect_punct(close_paren, Tokens2, Rest, CloseChildren, D2, D),
  append(OpenChildren, NameChildren, C1),
  append(C1, CloseChildren, Children).

name_list(Tokens, Tokens, [], D, D) :-
  ( peek_punct(Tokens, close_paren) ; peek(Tokens, eof) ), !.
name_list(Tokens, Rest, Children, D0, D) :-
  peek(Tokens, ident), !,
  bump(Tokens, Tokens1, NameChildren),
  name_list(Tokens1, Rest, More, D0, D),
  append(NameChildren, More, Children).
name_list(Tokens, Rest, [node(error, Err) | More], D0, D) :-
  offset(Tokens, At),
  bump(Tokens, Tokens1, Err),
  name_list(Tokens1, Rest, More, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

% ===========================================================================
% public PREFIX  (on external / module / type / definition)
% ===========================================================================

public_item(Tokens, Rest, node(public, Children), D0, D) :-
  bump(Tokens, Tokens1, PublicChildren),          % `public`
  ( item(Tokens1, Tokens2, Inner, D0, D) -> true
  ; expression(0, Tokens1, Tokens2, Inner, D0, D) ),
  append(PublicChildren, [Inner], Children),
  Rest = Tokens2.

% ===========================================================================
% external NAME : TYPE [= 'js'] [from 'mod']
% ===========================================================================

external_declaration(Tokens, Rest, node(external, Children), D0, D) :-
  bump(Tokens, Tokens1, ExtChildren),             % `external`
  expect_kind(ident, Tokens1, Tokens2, NameChildren, D0, D1),
  expect_punct(colon, Tokens2, Tokens3, ColonChildren, D1, D2),
  type_expression(Tokens3, Tokens4, TypeNode, D2, D3),
  external_source(Tokens4, Rest, SourceChildren, D3, D),
  append(ExtChildren, NameChildren, C1),
  append(C1, ColonChildren, C2),
  append(C2, [TypeNode], C3),
  append(C3, SourceChildren, Children).

% `= 'expr'`, `from 'mod'`, `= 'name' from 'mod'`, or nothing (ambient global).
external_source(Tokens, Rest, Children, D0, D) :-
  ( peek_punct(Tokens, eq) ->
      bump(Tokens, T1, EqCh),
      expect_kind(string, T1, T2, StrCh, D0, D1),
      from_clause(T2, Rest, FromCh, D1, D),
      append(EqCh, StrCh, C1), append(C1, FromCh, Children)
  ; keyword(Tokens, "from") ->
      from_clause(Tokens, Rest, Children, D0, D)
  ; Children = [], Rest = Tokens, D0 = D ).

from_clause(Tokens, Rest, Children, D0, D) :-
  ( keyword(Tokens, "from") ->
      bump(Tokens, T1, FromCh),
      expect_kind(string, T1, Rest, StrCh, D0, D),
      append(FromCh, StrCh, Children)
  ; Children = [], Rest = Tokens, D0 = D ).

% ===========================================================================
% type NAME TypeParameters? = DeclarationBody
%   DeclarationBody :- VariantBody | "opaque"? TypeExpression
%   VariantBody     :- "|"? Constructor ("|" Constructor)*
%   Constructor     :- Identifier ("(" TypeExpression+ ")")?
% ===========================================================================

type_declaration(Tokens, Rest, node(type_declaration, Children), D0, D) :-
  bump(Tokens, Tokens1, TypeChildren),            % `type`
  expect_kind(ident, Tokens1, Tokens2, NameChildren, D1a, D1),
  ( peek_punct(Tokens2, open_angle) ->            % optional type parameters
      type_parameters(Tokens2, Tokens3, ParamsNode, D0, D1a),
      ParamPart = [ParamsNode]
  ; ParamPart = [], Tokens3 = Tokens2, D0 = D1a ),
  expect_punct(eq, Tokens3, Tokens4, EqChildren, D1, D2),
  type_body(Tokens4, Rest, BodyChildren, D2, D),
  append(TypeChildren, NameChildren, C1),
  append(C1, ParamPart, C2),
  append(C2, EqChildren, C3),
  append(C3, BodyChildren, Children).

% A variant body when it starts with `|`, or is a single constructor written
% with a field list (`Wrap(number)`), or a bare constructor followed by `|`
% (`Red | Green`).  Otherwise the body is an (optionally `opaque`) alias type.
% `opaque` is checked FIRST: it is the opacity marker of an alias body, never a
% constructor name, so `type X = opaque (..)` must not be read as a variant whose
% first constructor is `opaque(..)`.
type_body(Tokens, Rest, Children, D0, D) :-
  ( keyword(Tokens, "opaque") ->
      bump(Tokens, T1, OpaqueCh),
      type_expression(T1, Rest, TypeNode, D0, D),
      Children = [node(opaque, OpaqueCh), TypeNode]
  ; variant_lookahead(Tokens) ->
      variants(Tokens, Rest, Children, D0, D)
  ; type_expression(Tokens, Rest, TypeNode, D0, D),
      Children = [TypeNode] ).

variant_lookahead(Tokens) :- peek_punct(Tokens, bar), !.
variant_lookahead(Tokens) :-
  skip_trivia(Tokens, _, [t(ident, _, _, _) | AfterIdent]),
  skip_trivia(AfterIdent, _, [t(Kind, _, _, _) | _]),
  ( punct(open_paren, Kind) ; punct(bar, Kind) ).

% VariantBody: optional leading `|`, then constructors separated by `|`.
variants(Tokens, Rest, Children, D0, D) :-
  ( peek_punct(Tokens, bar) -> bump(Tokens, T1, LeadBar) ; LeadBar = [], T1 = Tokens ),
  constructor_node(T1, T2, Ctor, D0, D1),
  variants_rest(T2, Rest, More, D1, D),
  append(LeadBar, [Ctor | More], Children).

variants_rest(Tokens, Rest, Children, D0, D) :-
  peek_punct(Tokens, bar), !,
  bump(Tokens, T1, BarCh),
  constructor_node(T1, T2, Ctor, D0, D1),
  variants_rest(T2, Rest, More, D1, D),
  append(BarCh, [Ctor | More], Children).
variants_rest(Rest, Rest, [], D, D).

constructor_node(Tokens, Rest, node(variant, Children), D0, D) :-
  expect_kind(ident, Tokens, T1, NameCh, D0, D1),
  ( peek_punct(T1, open_paren) ->
      bump(T1, T2, OpenCh),
      type_sequence(T2, T3, FieldCh, D1, D2),
      expect_punct(close_paren, T3, Rest, CloseCh, D2, D),
      append(OpenCh, FieldCh, F1), append(F1, CloseCh, ArgCh)
  ; ArgCh = [], Rest = T1, D1 = D ),
  append(NameCh, ArgCh, Children).

% ===========================================================================
% module NAME = ( items )
% ===========================================================================

module_declaration(Tokens, Rest, node(module, Children), D0, D) :-
  bump(Tokens, Tokens1, ModuleChildren),          % `module`
  expect_kind(ident, Tokens1, Tokens2, NameChildren, D0, D1),
  expect_punct(eq, Tokens2, Tokens3, EqChildren, D1, D2),
  expect_punct(open_paren, Tokens3, Tokens4, OpenChildren, D2, D3),
  module_items(Tokens4, Tokens5, BodyChildren, D3, D4),
  expect_punct(close_paren, Tokens5, Rest, CloseChildren, D4, D),
  append(ModuleChildren, NameChildren, C1),
  append(C1, EqChildren, C2),
  append(C2, OpenChildren, C3),
  append(C3, BodyChildren, C4),
  append(C4, CloseChildren, Children).

% Like `items`, but stops at the closing `)` of the module body.
module_items(Tokens, Tokens, [], D, D) :-
  ( peek_punct(Tokens, close_paren) ; peek(Tokens, eof) ), !.
module_items(Tokens, Rest, [Item | Items], D0, D) :-
  item(Tokens, Tokens1, Item, D0, D1), !,
  module_items(Tokens1, Rest, Items, D1, D).
module_items(Tokens, Rest, [node(error, Err) | Items], D0, D) :-
  offset(Tokens, At),
  bump(Tokens, Tokens1, Err),
  module_items(Tokens1, Rest, Items, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

% ===========================================================================
% Expressions -- precedence climbing.
% ===========================================================================

expression(MinPrec, Tokens, Rest, Node, D0, D) :-
  unary_expression(Tokens, Tokens1, Left, D0, D1),
  infix_loop(MinPrec, Left, Tokens1, Rest, Node, D1, D).

unary_expression(Tokens, Rest, Node, D0, D) :-
  peek(Tokens, Kind),
  ( unary_operator(Kind) ->
      bump(Tokens, Tokens1, OpChildren),
      unary_expression(Tokens1, Rest, Operand, D0, D),
      append(OpChildren, [Operand], Children),
      Node = node(unary, Children)
  ; postfix_expression(Tokens, Rest, Node, D0, D)
  ).

postfix_expression(Tokens, Rest, Node, D0, D) :-
  atom_expression(Tokens, Tokens1, Atom, D0, D1),
  postfix_chain(Atom, Tokens1, Rest, Node, D1, D).

postfix_chain(Acc, Tokens, Rest, Node, D0, D) :-
  ( postfixable(Acc), peek_punct(Tokens, dot) ->
      bump(Tokens, Tokens1, DotChildren),
      expect_kind(ident, Tokens1, Tokens2, NameChildren, D0, D1),
      append([Acc | DotChildren], NameChildren, Children),
      postfix_chain(node(access, Children), Tokens2, Rest, Node, D1, D)
  ; postfixable(Acc), peek_punct(Tokens, open_paren) ->
      argument_list(Tokens, Tokens1, ArgChildren, D0, D1),
      postfix_chain(node(call, [Acc | ArgChildren]), Tokens1, Rest, Node, D1, D)
  ; Node = Acc, Rest = Tokens, D0 = D
  ).

% A `.access`/`(call)` may follow a value atom but NOT a statement-like atom: a
% block / if / match / quasiquote / function-literal is not directly postfixed.
% Crucially this stops a function `(a): T { ... }` (or `(a): T expr`) from
% swallowing the next statement's leading `( ... )` as a call -- the batch
% parser only avoided that via full-consumption backtracking.  (A function value
% is still callable through a name or a parenthesised sub-expression.)
postfixable(node(Kind, _)) :-
  \+ member(Kind, [block, conditional, match, quote, unquote, function]).

argument_list(Tokens, Rest, Children, D0, D) :-
  bump(Tokens, Tokens1, OpenChildren),            % `(`
  expression_sequence(close_paren, Tokens1, Tokens2, ArgNodes, D0, D1),
  expect_punct(close_paren, Tokens2, Rest, CloseChildren, D1, D),
  append(OpenChildren, ArgNodes, C1),
  append(C1, CloseChildren, Children).

% A run of space-separated expressions terminated by the named closer.
expression_sequence(Closer, Tokens, Tokens, [], D, D) :-
  ( peek_punct(Tokens, Closer) ; peek(Tokens, eof) ), !.
expression_sequence(Closer, Tokens, Rest, [Item | Items], D0, D) :-
  peek(Tokens, Kind), ( starts_expression(Tokens, Kind) ; keyword_expr(Tokens) ), !,
  expression(1, Tokens, Tokens1, Item, D0, D1),   % >0: `=` is a member binding, not a separator
  expression_sequence(Closer, Tokens1, Rest, Items, D1, D).
expression_sequence(Closer, Tokens, Rest, [node(error, Err) | Items], D0, D) :-
  offset(Tokens, At),
  bump(Tokens, Tokens1, Err),
  expression_sequence(Closer, Tokens1, Rest, Items, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

keyword_expr(Tokens) :- ( keyword(Tokens, "if") ; keyword(Tokens, "match") ).

infix_loop(MinPrec, Left, Tokens, Rest, Node, D0, D) :-
  peek(Tokens, Kind),
  ( binary_operator(Kind, Prec, Assoc), Prec >= MinPrec ->
      bump(Tokens, Tokens1, OpChildren),
      ( Assoc == left -> NextMin is Prec + 1 ; NextMin = Prec ),
      expression(NextMin, Tokens1, Tokens2, Right, D0, D1),
      append([Left | OpChildren], [Right], Children),
      ( punct(eq, Kind) -> NodeKind = definition ; NodeKind = binary ),
      infix_loop(MinPrec, node(NodeKind, Children), Tokens2, Rest, Node, D1, D)
  ; Node = Left, Rest = Tokens, D0 = D
  ).

% ===========================================================================
% Atoms (including the keyword expressions `if` and `match`, and the `(...)`
% form which is a tuple/record OR a function literal when followed by `:`).
% ===========================================================================

atom_expression(Tokens, Rest, Node, D0, D) :-
  ( keyword(Tokens, "if")    -> if_expression(Tokens, Rest, Node, D0, D)
  ; keyword(Tokens, "match") -> match_expression(Tokens, Rest, Node, D0, D)
  ; peek_punct(Tokens, at)       -> macro_invocation(Tokens, Rest, Node, D0, D)
  ; peek_punct(Tokens, backtick) -> quasiquote(Tokens, Rest, Node, D0, D)
  ; peek_punct(Tokens, tilde)    -> unquote(Tokens, Rest, Node, D0, D)
  ; peek(Tokens, number)     -> bump(Tokens, Rest, Ch), Node = node(number, Ch), D0 = D
  ; peek(Tokens, string)     -> bump(Tokens, Rest, Ch), Node = node(string, Ch), D0 = D
  ; peek(Tokens, ident)      -> bump(Tokens, Rest, Ch), Node = node(identifier, Ch), D0 = D
  ; peek(Tokens, underscore) -> bump(Tokens, Rest, Ch), Node = node(placeholder, Ch), D0 = D
  ; peek_punct(Tokens, open_paren) -> paren_or_function(Tokens, Rest, Node, D0, D)
  ; peek_punct(Tokens, open_angle) -> generic_function(Tokens, Rest, Node, D0, D)
  ; peek_punct(Tokens, open_brace) -> block(Tokens, Rest, Node, D0, D)
  ; closing_or_eof(Tokens) ->
      offset(Tokens, At),
      Node = node(error, [t(missing, [], At, At)]),
      Rest = Tokens,
      D0 = [diagnostic(At, At, expected_expression) | D]
  ;   offset(Tokens, At),
      bump(Tokens, Rest, Ch),
      Node = node(error, Ch),
      D0 = [diagnostic(At, At, expected_expression) | D]
  ).

closing_or_eof(Tokens) :-
  ( peek_punct(Tokens, close_paren)
  ; peek_punct(Tokens, close_brace)
  ; peek(Tokens, eof) ).

% if COND THEN else ELSE
if_expression(Tokens, Rest, node(conditional, Children), D0, D) :-
  bump(Tokens, T1, IfCh),
  expression(1, T1, T2, Cond, D0, D1),            % >0 so a following `=` is not swallowed
  expression(1, T2, T3, Then, D1, D2),
  ( keyword(T3, "else") ->
      bump(T3, T4, ElseCh),
      expression(0, T4, Rest, Else, D2, D),
      append(IfCh, [Cond], C1), append(C1, [Then], C2),
      append(C2, ElseCh, C3), append(C3, [Else], Children)
  ; offset(T3, At),
    append(IfCh, [Cond], C1), append(C1, [Then], C2),
    append(C2, [t(missing, [], At, At)], Children),
    Rest = T3, D2 = [diagnostic(At, At, expected(else)) | D] ).

% match SCRUTINEE  (| PATTERN => RESULT)+
match_expression(Tokens, Rest, node(match, Children), D0, D) :-
  bump(Tokens, T1, MatchCh),
  % The scrutinee is parsed at the postfix level so it never consumes a `|`.
  postfix_expression(T1, T2, Scrutinee, D0, D1),
  match_arms(T2, Rest, ArmChildren, D1, D),
  append(MatchCh, [Scrutinee], C1),
  append(C1, ArmChildren, Children).

match_arms(Tokens, Rest, [node(arm, ArmChildren) | More], D0, D) :-
  peek_punct(Tokens, bar), !,
  bump(Tokens, T1, BarCh),
  pattern(T1, T2, Pat, D0, D1),
  expect_punct(arrow, T2, T3, ArrowCh, D1, D2),
  % Result parsed above precedence 2 so it does NOT consume the `|` that
  % separates the next arm (the binary-or operator and the arm separator share
  % the `|` token; in a match arm the separator wins).
  expression(3, T3, T4, Result, D2, D3),
  append(BarCh, [Pat], C1), append(C1, ArrowCh, C2), append(C2, [Result], ArmChildren),
  match_arms(T4, Rest, More, D3, D).
match_arms(Rest, Rest, [], D, D).

% ===========================================================================
% Patterns (match arms):  _ | NUMBER | STRING | Name | Ctor(subpattern*) | (pat*)
% ===========================================================================

pattern(Tokens, Rest, Node, D0, D) :-
  ( peek(Tokens, underscore) -> bump(Tokens, Rest, Ch), Node = node(wildcard_pattern, Ch), D0 = D
  ; peek(Tokens, number) -> bump(Tokens, Rest, Ch), Node = node(literal_pattern, Ch), D0 = D
  ; peek(Tokens, string) -> bump(Tokens, Rest, Ch), Node = node(literal_pattern, Ch), D0 = D
  ; peek(Tokens, ident)  ->
      bump(Tokens, T1, NameCh),
      ( peek_punct(T1, open_paren) ->
          bump(T1, T2, OpenCh),
          pattern_sequence(T2, T3, SubCh, D0, D1),
          expect_punct(close_paren, T3, Rest, CloseCh, D1, D),
          append(NameCh, OpenCh, C1), append(C1, SubCh, C2), append(C2, CloseCh, Children),
          Node = node(constructor_pattern, Children)
      ; Node = node(binding_pattern, NameCh), Rest = T1, D0 = D )
  ; peek_punct(Tokens, open_paren) ->
      bump(Tokens, T1, OpenCh),
      pattern_sequence(T1, T2, SubCh, D0, D1),
      expect_punct(close_paren, T2, Rest, CloseCh, D1, D),
      append(OpenCh, SubCh, C1), append(C1, CloseCh, Children),
      Node = node(tuple_pattern, Children)
  ;   offset(Tokens, At),
      Node = node(error, [t(missing, [], At, At)]), Rest = Tokens,
      D0 = [diagnostic(At, At, expected_pattern) | D]
  ).

pattern_sequence(Tokens, Tokens, [], D, D) :-
  ( peek_punct(Tokens, close_paren) ; peek(Tokens, eof) ), !.
pattern_sequence(Tokens, Rest, [Pat | Pats], D0, D) :-
  ( peek(Tokens, number) ; peek(Tokens, string) ; peek(Tokens, ident)
  ; peek(Tokens, underscore) ; peek_punct(Tokens, open_paren) ), !,
  pattern(Tokens, Tokens1, Pat, D0, D1),
  pattern_sequence(Tokens1, Rest, Pats, D1, D).
pattern_sequence(Tokens, Rest, [node(error, Err) | Pats], D0, D) :-
  offset(Tokens, At),
  bump(Tokens, Tokens1, Err),
  pattern_sequence(Tokens1, Rest, Pats, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

% ===========================================================================
% Parenthesised form: tuple / record literal, OR a function literal when the
% closing `)` is followed by `: returntype body`.
%
%   (a + b)                 -> paren
%   (10 20)  (x = 1 y = 2)  -> tuple / record (space-separated members)
%   (a: number b: number): number  BODY   -> function
%
% Members are space-separated; a member may carry a `: type` annotation and an
% optional `mutable`/`readonly` prefix.
% ===========================================================================

paren_or_function(Tokens, Rest, Node, D0, D) :-
  bump(Tokens, T1, OpenCh),
  member_sequence(T1, T2, MemberChildren, D0, D1),
  expect_punct(close_paren, T2, T3, CloseCh, D1, D2),
  append(OpenCh, MemberChildren, C1),
  append(C1, CloseCh, GroupChildren),
  ( peek_punct(T3, colon) ->
      % Function literal: the `(...)` were parameters; parse `: rettype body`.
      bump(T3, T4, ColonCh),
      type_expression(T4, T5, RetType, D2, D3),
      expression(0, T5, Rest, Body, D3, D),
      append(GroupChildren, ColonCh, F1),
      append(F1, [RetType], F2),
      append(F2, [Body], Children),
      Node = node(function, Children)
  ; Node = node(group, GroupChildren), Rest = T3, D2 = D ).

% A function literal with leading generics:  <A ..> ( params ) : Ret  Body
% The `<...>` makes it unambiguously a function (not a comparison), so -- unlike
% the bare `(...)` form -- no `(...):` lookahead is needed to commit.
generic_function(Tokens, Rest, node(function, Children), D0, D) :-
  type_parameters(Tokens, T1, Params, D0, D1),
  expect_punct(open_paren, T1, T2, OpenCh, D1, D2),
  member_sequence(T2, T3, MemberChildren, D2, D3),
  expect_punct(close_paren, T3, T4, CloseCh, D3, D4),
  expect_punct(colon, T4, T5, ColonCh, D4, D5),
  type_expression(T5, T6, RetType, D5, D6),
  expression(0, T6, Rest, Body, D6, D),
  append([Params | OpenCh], MemberChildren, C1),
  append(C1, CloseCh, C2),
  append(C2, ColonCh, C3),
  append(C3, [RetType, Body], Children).

member_sequence(Tokens, Tokens, [], D, D) :-
  ( peek_punct(Tokens, close_paren) ; peek(Tokens, eof) ), !.
member_sequence(Tokens, Rest, [Member | Members], D0, D) :-
  ( keyword(Tokens, "mutable") ; keyword(Tokens, "readonly")
  ; peek(Tokens, Kind), starts_expression(Tokens, Kind) ; keyword_expr(Tokens) ), !,
  member_item(Tokens, Tokens1, Member, D0, D1),
  member_sequence(Tokens1, Rest, Members, D1, D).
member_sequence(Tokens, Rest, [node(error, Err) | Members], D0, D) :-
  offset(Tokens, At),
  bump(Tokens, Tokens1, Err),
  member_sequence(Tokens1, Rest, Members, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

member_item(Tokens, Rest, node(member, Children), D0, D) :-
  ( ( keyword(Tokens, "mutable") ; keyword(Tokens, "readonly") ) ->
      bump(Tokens, T1, ModCh)
  ; ModCh = [], T1 = Tokens ),
  % expression(0) so a record binding `x = 1` is parsed whole (as a `definition`
  % node via the `=` operator); a plain tuple member or a parameter name has no
  % `=`, and a parameter annotation `name : type` is picked up by the `:` branch
  % below (the `:` is not a binary operator, so expression(0) stops before it).
  expression(0, T1, T2, Expr, D0, D1),
  ( peek_punct(T2, colon) ->
      bump(T2, T3, ColonCh),
      type_expression(T3, Rest, TypeNode, D1, D),
      append(ModCh, [Expr], C1), append(C1, ColonCh, C2), append(C2, [TypeNode], Children)
  ; Rest = T2, D1 = D, append(ModCh, [Expr], Children) ).

% ===========================================================================
% Blocks:  { item* }
% ===========================================================================

block(Tokens, Rest, node(block, Children), D0, D) :-
  bump(Tokens, T1, OpenCh),
  block_items(T1, T2, ItemChildren, D0, D1),
  expect_punct(close_brace, T2, Rest, CloseCh, D1, D),
  append(OpenCh, ItemChildren, C1),
  append(C1, CloseCh, Children).

block_items(Tokens, Tokens, [], D, D) :-
  ( peek_punct(Tokens, close_brace) ; peek(Tokens, eof) ), !.
block_items(Tokens, Rest, [Item | Items], D0, D) :-
  ( item(Tokens, Tokens1, Item, D0, D1) -> true
  ; expression(0, Tokens, Tokens1, Item, D0, D1) ), !,
  block_items(Tokens1, Rest, Items, D1, D).
block_items(Tokens, Rest, [node(error, Err) | Items], D0, D) :-
  offset(Tokens, At),
  bump(Tokens, Tokens1, Err),
  block_items(Tokens1, Rest, Items, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

% ===========================================================================
% Type expressions.  Full surface grammar (see `grammar`):
%   TypeExpression  :- QuantifiedType | ParenthesizedType | TypeReference
%   QuantifiedType  :- TypeParameters TypeExpression               <A>(A): A
%   ParenthesizedType :- "(" TypeMember* (".." Id?)? ")" (":" Type)?
%                          tuple / open record / function type
%   TypeReference   :- QualifiedName TypeArguments?                Box<number>
%   TypeArguments   :- "<" (TypeArgument)+ ">"   TypeArgument :- "_" | Type
% `..` is two `.` tokens (the lexer has no `..`); `<`/`>` are the same tokens as
% the comparison operators but here are structural.
% ===========================================================================

% The lexer greedily forms `>>` / `>=` (the shift / comparison operators), so a
% closing `>` of a NESTED type application (`Box<Box<number>>`) can be hiding at
% the front of one of those tokens.  `at_close_angle` recognises any token whose
% text starts with `>` as "a close is here"; `close_angle` consumes one `>`,
% SPLITTING a `>>`/`>=` token and pushing the remainder back so it can close the
% enclosing list (or be read as `=` / `>`).  The split halves' text concatenates
% to the original, so the tree stays lossless.
at_close_angle(Tokens) :-
  skip_trivia(Tokens, _, [t(_, ['>' | _], _, _) | _]).

close_angle(Tokens, Rest, Children, D0, D) :-
  skip_trivia(Tokens, Trivia, [Tok | After]),
  ( Tok = t(_, ['>'], _, _) ->                         % a lone `>`
      append(Trivia, [Tok], Children), Rest = After, D0 = D
  ; split_close(Tok, GtToken, RestToken) ->            % `>>`, `>=`, ...
      append(Trivia, [GtToken], Children), Rest = [RestToken | After], D0 = D
  ; offset(Tokens, At),
    Children = [t(missing, [], At, At)], Rest = Tokens,
    D0 = [diagnostic(At, At, expected('>')) | D] ).

split_close(t(_, ['>', C | Cs], Start, End), t('>', ['>'], Start, Mid), t(RestKind, [C | Cs], Mid, End)) :-
  Mid is Start + 1,
  atom_chars(RestKind, [C | Cs]).

type_expression(Tokens, Rest, Node, D0, D) :-
  ( peek_punct(Tokens, open_angle) ->                 % quantified (polymorphic)
      type_parameters(Tokens, T1, Params, D0, D1),
      type_expression(T1, Rest, Body, D1, D),
      Node = node(quantified_type, [Params, Body])
  ; type_atom(Tokens, T1, Atom, D0, D1),
    ( peek_punct(T1, colon) ->                         % function type:  (..) : Ret
        bump(T1, T2, ColonCh),
        type_expression(T2, Rest, Result, D1, D),
        append([Atom | ColonCh], [Result], Children),
        Node = node(function_type, Children)
    ; Node = Atom, Rest = T1, D1 = D ) ).

type_atom(Tokens, Rest, Node, D0, D) :-
  ( peek(Tokens, ident) -> type_reference(Tokens, Rest, Node, D0, D)
  ; peek_punct(Tokens, open_paren) -> parenthesized_type(Tokens, Rest, Node, D0, D)
  ;   offset(Tokens, At),
      Node = node(error, [t(missing, [], At, At)]), Rest = Tokens,
      D0 = [diagnostic(At, At, expected_type) | D] ).

% A named reference: a (possibly qualified `a.B`) name, optionally applied to
% angle-bracketed type arguments.
type_reference(Tokens, Rest, node(type_name, Children), D0, D) :-
  qualified_type_name(Tokens, T1, NameCh),
  ( peek_punct(T1, open_angle) ->
      type_arguments(T1, Rest, ArgsNode, D0, D),
      append(NameCh, [ArgsNode], Children)
  ; Rest = T1, D0 = D, Children = NameCh ).

% ident ("." ident)*  -- in a type position a `.` always qualifies the name.
qualified_type_name(Tokens, Rest, Children) :-
  bump(Tokens, T1, IdCh),
  (   peek_punct(T1, dot),
      skip_trivia(T1, _, [_Dot | AfterDot]), skip_trivia(AfterDot, _, [t(ident, _, _, _) | _])
  ->  bump(T1, T2, DotCh),
      qualified_type_name(T2, Rest, RestCh),
      append(IdCh, DotCh, C1), append(C1, RestCh, Children)
  ;   Rest = T1, Children = IdCh ).

type_arguments(Tokens, Rest, node(type_args, Children), D0, D) :-
  bump(Tokens, T1, OpenCh),                            % `<`
  type_arg_seq(T1, T2, ArgChildren, D0, D1),
  close_angle(T2, Rest, CloseCh, D1, D),
  append(OpenCh, ArgChildren, C1), append(C1, CloseCh, Children).

type_arg_seq(Tokens, Tokens, [], D, D) :-
  ( at_close_angle(Tokens) ; peek(Tokens, eof) ), !.
type_arg_seq(Tokens, Rest, [node(type_hole, HoleCh) | Args], D0, D) :-
  peek(Tokens, underscore), !,
  bump(Tokens, T1, HoleCh),
  type_arg_seq(T1, Rest, Args, D0, D).
type_arg_seq(Tokens, Rest, [Arg | Args], D0, D) :-
  type_starts(Tokens), !,
  type_expression(Tokens, T1, Arg, D0, D1),
  type_arg_seq(T1, Rest, Args, D1, D).
type_arg_seq(Tokens, Rest, [node(error, Err) | Args], D0, D) :-
  offset(Tokens, At), bump(Tokens, T1, Err),
  type_arg_seq(T1, Rest, Args, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

% A type expression can begin with an identifier, `(`, or `<` (quantified).
type_starts(Tokens) :-
  ( peek(Tokens, ident) ; peek_punct(Tokens, open_paren) ; peek_punct(Tokens, open_angle) ).

% A parenthesized type: a tuple/record type, optionally open (`.. R?`), and a
% function type when a `: ReturnType` follows.
parenthesized_type(Tokens, Rest, Node, D0, D) :-
  bump(Tokens, T1, OpenCh),                            % `(`
  type_member_seq(T1, T2, MemberChildren, D0, D1),
  type_rest_opt(T2, T3, RestChildren, D1, D2),         % optional `.. R?`
  expect_punct(close_paren, T3, T4, CloseCh, D2, D3),
  append(OpenCh, MemberChildren, C1), append(C1, RestChildren, C2), append(C2, CloseCh, TupleChildren),
  Tuple = node(type_tuple, TupleChildren),
  ( peek_punct(T4, colon) ->
      bump(T4, T5, ColonCh),
      type_expression(T5, Rest, Ret, D3, D),
      append([Tuple | ColonCh], [Ret], FChildren),
      Node = node(function_type, FChildren)
  ; Node = Tuple, Rest = T4, D3 = D ).

% Members stop at `)` or the open-record `..` (a leading `.`).
type_member_seq(Tokens, Tokens, [], D, D) :-
  ( peek_punct(Tokens, close_paren) ; peek_punct(Tokens, dot) ; peek(Tokens, eof) ), !.
type_member_seq(Tokens, Rest, [Member | Members], D0, D) :-
  ( keyword(Tokens, "mutable") ; keyword(Tokens, "readonly") ; type_starts(Tokens) ), !,
  type_member(Tokens, T1, Member, D0, D1),
  type_member_seq(T1, Rest, Members, D1, D).
type_member_seq(Tokens, Rest, [node(error, Err) | Members], D0, D) :-
  offset(Tokens, At), bump(Tokens, T1, Err),
  type_member_seq(T1, Rest, Members, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

% Mutability? (Identifier ":" Type | Type).  Mutability and the label are kept
% in their own wrapper nodes so the lowerer can read them unambiguously.
type_member(Tokens, Rest, node(type_member, Children), D0, D) :-
  ( ( keyword(Tokens, "mutable") ; keyword(Tokens, "readonly") ) ->
      bump(Tokens, T1, ModCh), Mod = [node(mutability, ModCh)]
  ; Mod = [], T1 = Tokens ),
  ( labeled_member(T1) ->
      bump(T1, T2, LabelCh), bump(T2, T3, ColonCh),
      append(LabelCh, ColonCh, LabelNodeCh),
      type_expression(T3, Rest, TypeNode, D0, D),
      append(Mod, [node(type_label, LabelNodeCh), TypeNode], Children)
  ; type_expression(T1, Rest, TypeNode, D0, D),
      append(Mod, [TypeNode], Children) ).

% A labeled member is an identifier IMMEDIATELY followed by `:` (a positional
% member that is a named type is just the identifier, with no following `:`).
labeled_member(Tokens) :-
  skip_trivia(Tokens, _, [t(ident, _, _, _) | AfterIdent]),
  skip_trivia(AfterIdent, _, [t(Kind, _, _, _) | _]),
  punct(colon, Kind).

% The open-record tail `.. R?` (two `.` tokens, optional capture identifier).
type_rest_opt(Tokens, Rest, [node(type_rest, RestCh)], D0, D) :-
  peek_punct(Tokens, dot), !,
  bump(Tokens, T1, Dot1),
  expect_punct(dot, T1, T2, Dot2, D0, D1),
  ( peek(T2, ident) -> bump(T2, Rest, IdCh) ; IdCh = [], Rest = T2 ),
  D1 = D,
  append(Dot1, Dot2, C1), append(C1, IdCh, RestCh).
type_rest_opt(Tokens, Tokens, [], D, D).

% Type-argument / constructor-field sequence: space-separated type expressions.
type_sequence(Tokens, Tokens, [], D, D) :-
  ( peek_punct(Tokens, close_paren) ; peek(Tokens, eof) ), !.
type_sequence(Tokens, Rest, [Type | Types], D0, D) :-
  type_starts(Tokens), !,
  type_expression(Tokens, Tokens1, Type, D0, D1),
  type_sequence(Tokens1, Rest, Types, D1, D).
type_sequence(Tokens, Rest, [node(error, Err) | Types], D0, D) :-
  offset(Tokens, At),
  bump(Tokens, Tokens1, Err),
  type_sequence(Tokens1, Rest, Types, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

% ===========================================================================
% Type parameters:  "<" TypeParameter+ ">"
%   TypeParameter :- Identifier ("<" "_"+ ">" | (":" TypeExpression)?)
% A `<_ .. _>` suffix makes the parameter higher-kinded (its arity = #holes);
% a `: Type` gives a bound; otherwise it is a proper, unbounded parameter.
% ===========================================================================

type_parameters(Tokens, Rest, node(type_params, Children), D0, D) :-
  bump(Tokens, T1, OpenCh),                            % `<`
  type_param_seq(T1, T2, ParamChildren, D0, D1),
  close_angle(T2, Rest, CloseCh, D1, D),
  append(OpenCh, ParamChildren, C1), append(C1, CloseCh, Children).

type_param_seq(Tokens, Tokens, [], D, D) :-
  ( at_close_angle(Tokens) ; peek(Tokens, eof) ), !.
type_param_seq(Tokens, Rest, [Param | Params], D0, D) :-
  peek(Tokens, ident), !,
  type_parameter(Tokens, T1, Param, D0, D1),
  type_param_seq(T1, Rest, Params, D1, D).
type_param_seq(Tokens, Rest, [node(error, Err) | Params], D0, D) :-
  offset(Tokens, At), bump(Tokens, T1, Err),
  type_param_seq(T1, Rest, Params, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

type_parameter(Tokens, Rest, node(type_param, Children), D0, D) :-
  bump(Tokens, T1, NameCh),                            % the parameter name
  ( peek_punct(T1, open_angle) ->                      % higher-kinded F<_ .. _>
      kind_holes(T1, Rest, KindCh, D0, D),
      append(NameCh, [node(type_param_kind, KindCh)], Children)
  ; peek_punct(T1, colon) ->                           % bounded  T: Bound
      bump(T1, T2, ColonCh),
      type_expression(T2, Rest, Bound, D0, D),
      append(NameCh, ColonCh, C1), append(C1, [Bound], Children)
  ; Rest = T1, D0 = D, Children = NameCh ).

kind_holes(Tokens, Rest, Children, D0, D) :-
  bump(Tokens, T1, OpenCh),                            % `<`
  hole_seq(T1, T2, HoleCh, D0, D1),
  close_angle(T2, Rest, CloseCh, D1, D),
  append(OpenCh, HoleCh, C1), append(C1, CloseCh, Children).

hole_seq(Tokens, Tokens, [], D, D) :-
  ( at_close_angle(Tokens) ; peek(Tokens, eof) ), !.
hole_seq(Tokens, Rest, Holes, D0, D) :-
  peek(Tokens, underscore), !,
  bump(Tokens, T1, HoleCh),
  hole_seq(T1, Rest, More, D0, D),
  append(HoleCh, More, Holes).
hole_seq(Tokens, Rest, [node(error, Err) | Holes], D0, D) :-
  offset(Tokens, At), bump(Tokens, T1, Err),
  hole_seq(T1, Rest, Holes, D1, D),
  D0 = [diagnostic(At, At, unexpected_token) | D1].

% ===========================================================================
% Reader macros.
%   DEFINITION (item):  [public] macro NAME = ( param* ) BODY
%   INVOCATION (atom):  @NAME( arg* ) FOLLOWING-EXPRESSION      (NAME may be
%                       qualified, e.g. @Math.inc)
%   QUASIQUOTE (atom):  `( EXPR )
%   UNQUOTE    (atom):  ~NAME  |  ~( EXPR )
% The FOLLOWING expression of an invocation is kept as a full subtree (its raw
% text is recoverable losslessly via green_text/2 for the expander).
% ===========================================================================

macro_declaration(Tokens, Rest, node(macro_definition, Children), D0, D) :-
  bump(Tokens, T1, MacroCh),                       % `macro`
  expect_kind(ident, T1, T2, NameCh, D0, D1),
  expect_punct(eq, T2, T3, EqCh, D1, D2),
  expect_punct(open_paren, T3, T4, OpenCh, D2, D3),
  name_list(T4, T5, ParamCh, D3, D4),              % bare parameter identifiers
  expect_punct(close_paren, T5, T6, CloseCh, D4, D5),
  expression(0, T6, Rest, Body, D5, D),
  append(MacroCh, NameCh, C1), append(C1, EqCh, C2), append(C2, OpenCh, C3),
  append(C3, ParamCh, C4), append(C4, CloseCh, C5), append(C5, [Body], Children).

macro_invocation(Tokens, Rest, node(macro_call, Children), D0, D) :-
  bump(Tokens, T1, AtCh),                          % `@`
  macro_name(T1, T2, NameCh, D0, D1),
  expect_punct(open_paren, T2, T3, OpenCh, D1, D2),
  expression_sequence(close_paren, T3, T4, ArgNodes, D2, D3),
  expect_punct(close_paren, T4, T5, CloseCh, D3, D4),
  expression(0, T5, Rest, Following, D4, D),        % the following expression
  append(AtCh, NameCh, C1), append(C1, OpenCh, C2), append(C2, ArgNodes, C3),
  append(C3, CloseCh, C4), append(C4, [Following], Children).

% A macro name: an identifier, optionally dotted (`Math.inc`).
macro_name(Tokens, Rest, Children, D0, D) :-
  expect_kind(ident, Tokens, T1, FirstCh, D0, D1),
  macro_name_tail(T1, Rest, RestCh, D1, D),
  append(FirstCh, RestCh, Children).

macro_name_tail(Tokens, Rest, Children, D0, D) :-
  ( peek_punct(Tokens, dot) ->
      bump(Tokens, T1, DotCh),
      expect_kind(ident, T1, T2, NameCh, D0, D1),
      macro_name_tail(T2, Rest, MoreCh, D1, D),
      append(DotCh, NameCh, C1), append(C1, MoreCh, Children)
  ; Children = [], Rest = Tokens, D0 = D ).

quasiquote(Tokens, Rest, node(quote, Children), D0, D) :-
  bump(Tokens, T1, TickCh),                        % `` ` ``
  expect_punct(open_paren, T1, T2, OpenCh, D0, D1),
  expression(0, T2, T3, Inner, D1, D2),
  expect_punct(close_paren, T3, Rest, CloseCh, D2, D),
  append(TickCh, OpenCh, C1), append(C1, [Inner], C2), append(C2, CloseCh, Children).

unquote(Tokens, Rest, node(unquote, Children), D0, D) :-
  bump(Tokens, T1, TildeCh),                       % `~`
  ( peek_punct(T1, open_paren) ->
      bump(T1, T2, OpenCh),
      expression(0, T2, T3, Inner, D0, D1),
      expect_punct(close_paren, T3, Rest, CloseCh, D1, D),
      append(TildeCh, OpenCh, C1), append(C1, [Inner], C2), append(C2, CloseCh, Children)
  ; peek(T1, ident) ->
      % Wrap the bare identifier in an `identifier` node so the unquoted operand
      % is always a NODE (consistent with `~(EXPR)`), which lowering relies on.
      bump(T1, Rest, NameCh), D0 = D,
      append(TildeCh, [node(identifier, NameCh)], Children)
  ; offset(T1, At),
    Rest = T1,
    D0 = [diagnostic(At, At, expected(unquote_operand)) | D],
    append(TildeCh, [t(missing, [], At, At)], Children)
  ).

% ===========================================================================
% Operator tables (precedences from source/parser/binary.pl; `=` lowest).
% ===========================================================================

unary_operator('-').
unary_operator('!').
% NOTE: `~` is NOT a unary operator here -- it introduces an UNQUOTE
% (`~x` / `~(e)`), handled in atom_expression.  (The batch grammar likewise
% tries unquote before the unary `~`, so `~x` always reads as an unquote.)

binary_operator('*',  12, left).
binary_operator('/',  12, left).
binary_operator('+',  11, left).
binary_operator('-',  11, left).
binary_operator('<<', 10, left).
binary_operator('>>', 10, left).
binary_operator('&&',  9, left).
binary_operator('^^',  8, left).
binary_operator('||',  7, left).
binary_operator('<=',  6, left).
binary_operator('<',   6, left).
binary_operator('>=',  6, left).
binary_operator('>',   6, left).
binary_operator('==',  5, left).
binary_operator('!=',  5, left).
binary_operator('&',   4, left).
binary_operator('^',   3, left).
binary_operator('|',   2, left).
binary_operator('->',  1, left).
binary_operator('=',   0, right).

% ===========================================================================
% Losslessness check.
% ===========================================================================

green_text(t(_Kind, Text, _S, _E), Text) :- !.
green_text(node(_Kind, Children), Text) :-
  green_text_list(Children, Text).

green_text_list([], []).
green_text_list([Child | Children], Text) :-
  green_text(Child, Head),
  green_text_list(Children, Tail),
  append(Head, Tail, Text).
