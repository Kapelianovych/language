:- module(macro_syntax, [
  macro_declaration//2,
  macro_invocation//2,
  quote_expression//2,
  unquote_expression//2
]).

/*  parser/macro_syntax.pl  --  Surface syntax for READER MACROS.

    A reader macro is a COMPILE-TIME function, written in the language itself,
    that turns the raw source text following its invocation into program AST.
    It is the language's metaprogramming hook: it lets a user grow new syntax
    (a DSL) without changing the compiler.  See `transformation/macro.pl` for
    how invocations are expanded, and `builtin/compiler.sl`-style `Compiler`
    builtin (resolved in `module_loader.pl`) for the `Ast` type and the
    `parseItem` primitive a macro body uses.

    Four pieces of surface syntax are introduced here.  Each sub-parser takes
    the surrounding `ExpressionFunctor` (always `expression`) and parses nested
    expressions through it, so this module needs no (circular) dependency on
    `expression.pl`.

    1. MACRO DEFINITION  (a program item; see `program.pl`)

           [public] macro NAME = ( PARAM* ) BODY

       PARAMs are bare identifiers (no type annotations -- a macro body is
       interpreted, not type-checked).  BODY is an expression that must
       evaluate (at compile time) to an `Ast`.  Produces:

           macro_definition_node(NameChars, ParamNameChars, BodyExpr, Span)

       The LAST parameter conventionally receives the invocation's raw trailing
       `source` text; earlier parameters receive the `( ... )` arguments.  (The
       parser does not enforce this split -- the expander binds whatever
       parameters the definition declares; see `transformation/macro.pl`.)

    2. MACRO INVOCATION  (an expression)

           @NAME( ARG* ) FOLLOWING-EXPRESSION

       `@times(3) log('tick')` invokes macro `times` with the argument `3` and
       with `source` = the RAW SOURCE TEXT of the single expression that
       follows (`log('tick')`).  The following expression is parsed only to find
       its extent; its verbatim characters are captured (from the difference
       list) and handed to the macro as a string -- the macro re-parses them
       with `Compiler.parseItem` if it wants an `Ast`.  Produces:

           macro_call_node(NameChars, ArgExprs, SourceChars, Span)

       Capturing raw text (rather than parsing the source inline) is what lets
       expansion run as an ordinary POST-PARSE pass: no parse-time evaluation
       and no two-pass "install readers first" dance -- a macro may be defined
       anywhere in the file relative to its uses.

    3. QUASIQUOTE      `( EXPR )      -> quote_node(EXPR, Span)
    4. UNQUOTE         ~NAME | ~(EXPR) -> unquote_node(EXPR, Span)

       Inside a quasiquote, `~x` / `~(e)` splices an `Ast`-valued sub-result
       into the constructed AST.  The parens after the backtick (and the
       optional parens after `~`) are DELIMITERS of the quoted / unquoted
       expression, not tuple syntax.  Outside a quote, an unquote is a static
       error (reported by the expander), but it still parses here.
*/

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(identifier, [identifier//1, qualified_identifier//2]).
:- use_module(separator, [
  separator//0,
  separators//0
]).
:- use_module(position, [here//1, span_between/3]).

:- meta_predicate(macro_declaration(2, ?, ?, ?)).
:- meta_predicate(macro_invocation(2, ?, ?, ?)).
:- meta_predicate(quote_expression(2, ?, ?, ?)).
:- meta_predicate(unquote_expression(2, ?, ?, ?)).

% ---------------------------------------------------------------------------
% Definition:  [public] macro NAME = ( params ) body
% (`public` is handled by `program.pl`; here we parse from `macro`.)
% ---------------------------------------------------------------------------

macro_declaration(ExpressionFunctor, macro_definition_node(Name, Parameters, Body, Span)) -->
  here(Start),
  "macro",
  separator,            % mandatory: separates the soft keyword from the name
  separators,
  identifier(identifier_node(Name, _)),
  separators,
  "=",
  separators,
  "(",
  separators,
  macro_parameters(Parameters),
  separators,
  ")",
  separators,
  phrase(ExpressionFunctor, Body),
  here(End),
  { span_between(Start, End, Span) }.

macro_parameters([]) --> [].
macro_parameters([Name | Names]) -->
  identifier(identifier_node(Name, _)),
  macro_parameters_tail(Names).

macro_parameters_tail([]) --> [].
macro_parameters_tail([Name | Names]) -->
  separator,            % mandatory
  separators,
  identifier(identifier_node(Name, _)),
  macro_parameters_tail(Names).

% ---------------------------------------------------------------------------
% Invocation:  @NAME( args ) following-expression
% ---------------------------------------------------------------------------

macro_invocation(ExpressionFunctor, macro_call_node(Name, Arguments, Source, Span)) -->
  here(Start),
  "@",
  % The name may be QUALIFIED (`@macros.times`) for a macro reached through a
  % whole-module import; a bare `@times` is the single-segment case.
  qualified_identifier(Name, _),
  "(",
  separators,
  macro_arguments(ExpressionFunctor, Arguments),
  separators,
  ")",
  separators,
  % Capture the raw source of the FOLLOWING expression: parse it to find its
  % extent, then recover the verbatim characters it consumed from the
  % difference list (`SourceStart` minus the unconsumed `SourceEnd`).
  here(SourceStart),
  phrase(ExpressionFunctor, _Following),
  here(SourceEnd),
  { append(Source, SourceEnd, SourceStart),
    span_between(Start, SourceEnd, Span)
  }.

macro_arguments(_, []) --> [].
macro_arguments(ExpressionFunctor, [Argument | Arguments]) -->
  phrase(ExpressionFunctor, Argument),
  macro_arguments_tail(ExpressionFunctor, Arguments).

macro_arguments_tail(_, []) --> [].
macro_arguments_tail(ExpressionFunctor, [Argument | Arguments]) -->
  separator,            % mandatory
  separators,
  phrase(ExpressionFunctor, Argument),
  macro_arguments_tail(ExpressionFunctor, Arguments).

% ---------------------------------------------------------------------------
% Quasiquote:  `( EXPR )
% ---------------------------------------------------------------------------

quote_expression(ExpressionFunctor, quote_node(Inner, Span)) -->
  here(Start),
  "`",
  separators,
  "(",
  separators,
  phrase(ExpressionFunctor, Inner),
  separators,
  ")",
  here(End),
  { span_between(Start, End, Span) }.

% ---------------------------------------------------------------------------
% Unquote:  ~NAME  |  ~( EXPR )
% ---------------------------------------------------------------------------

unquote_expression(ExpressionFunctor, unquote_node(Inner, Span)) -->
  here(Start),
  "~",
  unquote_operand(ExpressionFunctor, Inner),
  here(End),
  { span_between(Start, End, Span) }.

% Parenthesised form first (so `~(a b)` groups), then a bare identifier.
unquote_operand(ExpressionFunctor, Inner) -->
  "(",
  separators,
  phrase(ExpressionFunctor, Inner),
  separators,
  ")".
unquote_operand(_ExpressionFunctor, Identifier) -->
  identifier(Identifier).
