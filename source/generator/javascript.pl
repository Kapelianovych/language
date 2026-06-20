:- module(javascript, [program//1]).

/*  javascript.pl  --  Emit JavaScript source for a parsed program.

    This is the code-generation (back-end) phase.  It walks the AST built by
    `source/parser` and produces JavaScript *as a list of characters* using a
    DCG: every rule appends the text it is responsible for to the output
    difference list.  `source/generator.pl` wraps this with `phrase/2` to
    hand back the finished string.

    --------------------------------------------------------------------
    TRANSLATION OVERVIEW
    --------------------------------------------------------------------
    AST node                JavaScript
    ----------------------  --------------------------------------------
    number_node(N)          numeric literal        42
    boolean_node(B)         true / false
    string_node(Parts)      template literal       `text ${expr}`
    identifier_node(Cs)     `$`-prefixed name      $counter
    function_node(Ps, B)    curried arrow          ($a => $b => <B>)
    function_call_node(T,A) curried application    ($f)($a)($b)
    tuple_node(Es)          array                  [e1, e2]
    block_node(Es)          IIFE returning last    (() => { ...; return e })()
    definition_node(I, V)   const binding          const $i = <V>;
    conditional_node(C,T,E) ternary                (c ? t : e)
    unary_node(Op, E)       (-E) / (!E) / (~E)
    binary_node(Op, L, R)   (L op R), or pipe as application

    WHY CURRYING.  The source language allows partial application: applying a
    two-argument function to one argument yields a one-argument function.
    Plain JS arrow functions do not curry, so we emit every multi-parameter
    function as a chain of single-argument arrows and every call as a chain of
    single-argument applications.  Then partial application, full application,
    over-application, recursion and the `->` pipe all work with no runtime
    helper -- they are just ordinary JavaScript.

    Every compound expression is wrapped in parentheses, which makes the
    output verbose but immune to JavaScript operator-precedence surprises.
*/

:- use_module(library(dcgs)).

% A whole program is a newline-separated sequence of top-level statements.
% Top-level definitions become `const` bindings; any other expression becomes
% an expression statement.  (The program is module-level code, so the value
% of the final expression is not returned anywhere.)
program(program_node(Expressions)) -->
  statements(Expressions).

statements([]) --> [].
statements([Expression | Expressions]) -->
  statement(Expression),
  "\n",
  statements(Expressions).

% A statement is either a `const` binding (for a definition) or an expression
% terminated by a semicolon.  The two clauses are mutually exclusive: the
% second is guarded so it never matches a definition.
statement(definition_node(identifier_node(Name), Value)) -->
  "const ", identifier(Name), " = ", expression(Value), ";".
statement(Expression) -->
  { Expression \= definition_node(_, _) },
  expression(Expression), ";".

% ---------------------------------------------------------------------------
% Expressions
% ---------------------------------------------------------------------------

% Numeric literal: reuse Prolog's own number printing, which yields valid
% JavaScript number syntax for the integers and floats the parser produces.
expression(number_node(Number)) -->
  { number_chars(Number, Chars) },
  chars(Chars).

expression(boolean_node(true)) --> "true".
expression(boolean_node(false)) --> "false".

% A variable reference.  See identifier//1 for the `$` prefix rationale.
expression(identifier_node(Name)) -->
  identifier(Name).

% String literal -> JavaScript template literal, so interpolation maps
% directly onto `${ ... }`.
expression(string_node(Parts)) -->
  "`", template_parts(Parts), "`".

% Lambda -> curried arrow function.  A nullary function stays nullary.
expression(function_node([], Body)) -->
  "(() => ", expression(Body), ")".
expression(function_node([Parameter | Parameters], Body)) -->
  "(", curried_arrows([Parameter | Parameters], Body), ")".

% Application -> curried call: the callee, then one parenthesised argument per
% argument.  A zero-argument call is emitted as `callee()`.
expression(function_call_node(Target, Arguments)) -->
  "(", expression(Target), ")", call_arguments(Arguments).

% Tuple -> array literal.  The empty tuple () is the unit value [].
expression(tuple_node(Elements)) -->
  "[", comma_separated(Elements), "]".

% Block -> an immediately-invoked arrow function that runs the inner
% statements and returns the value of the last expression.
expression(block_node(Expressions)) -->
  "(() => { ", block_body(Expressions), " })()".

% Conditional -> ternary expression.
expression(conditional_node(Condition, Then, Else)) -->
  "(", expression(Condition), " ? ", expression(Then), " : ", expression(Else), ")".

% Unary operator.
expression(unary_node(Operator, Operand)) -->
  "(", unary_operator(Operator), expression(Operand), ")".

% The pipe `x -> f` feeds `x` to `f`; with currying that is simply `f(x)`.
expression(binary_node(pipe, Left, Right)) -->
  "(", expression(Right), ")(", expression(Left), ")".
% Every other binary operator maps to an infix JavaScript operator.
expression(binary_node(Operator, Left, Right)) -->
  { Operator \= pipe },
  "(", expression(Left), " ", binary_operator(Operator), " ", expression(Right), ")".

% A definition reached in expression position (e.g. as a call argument) cannot
% introduce a visible binding, so we emit only its value -- matching the type
% checker, which gives such a definition the type of its value.
expression(definition_node(_Target, Value)) -->
  expression(Value).

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

% Curried arrow chain: `$p1 => $p2 => ... => <body>`.
curried_arrows([Parameter], Body) -->
  parameter(Parameter), " => ", expression(Body).
curried_arrows([Parameter, Next | Parameters], Body) -->
  parameter(Parameter), " => ", curried_arrows([Next | Parameters], Body).

parameter(identifier_node(Name)) -->
  identifier(Name).

% Curried application: `()` for no arguments, otherwise `(a)(b)(c)`.
call_arguments([]) --> "()".
call_arguments([Argument | Arguments]) -->
  argument_applications([Argument | Arguments]).

argument_applications([]) --> [].
argument_applications([Argument | Arguments]) -->
  "(", expression(Argument), ")", argument_applications(Arguments).

% Body of a block IIFE: leading statements, then a `return` of the last value.
block_body([]) --> [].
block_body([Expression]) -->
  return_statement(Expression).
block_body([Expression, Next | Expressions]) -->
  statement(Expression), " ", block_body([Next | Expressions]).

% The final element of a block is what the block evaluates to.  A trailing
% definition is still bound first (so a recursive function can refer to
% itself) and then returned.
return_statement(definition_node(identifier_node(Name), Value)) -->
  "const ", identifier(Name), " = ", expression(Value), "; return ", identifier(Name), ";".
return_statement(Expression) -->
  { Expression \= definition_node(_, _) },
  "return ", expression(Expression), ";".

% Comma-separated expressions, used for array elements.
comma_separated([]) --> [].
comma_separated([Expression]) -->
  expression(Expression).
comma_separated([Expression, Next | Expressions]) -->
  expression(Expression), ", ", comma_separated([Next | Expressions]).

% The alternating static / interpolated pieces of a string literal.
template_parts([]) --> [].
template_parts([string_static_part(Chars) | Parts]) -->
  escaped_template_text(Chars),
  template_parts(Parts).
template_parts([string_interpolated_part(Node) | Parts]) -->
  "${", expression(Node), "}",
  template_parts(Parts).

% Escape the three characters that are special inside a backtick template:
% backslash (92), backtick (96) and `$` (36, escaped to neutralise `${`).
escaped_template_text([]) --> [].
escaped_template_text([Char | Chars]) -->
  escaped_char(Char),
  escaped_template_text(Chars).

escaped_char(Char) --> { char_code(Char, 92) }, "\\\\".
escaped_char(Char) --> { char_code(Char, 96) }, "\\`".
escaped_char(Char) --> { char_code(Char, 36) }, "\\$".
escaped_char(Char) -->
  { char_code(Char, Code), Code =\= 92, Code =\= 96, Code =\= 36 },
  [Char].

% User identifiers are prefixed with `$` so they can never collide with a
% JavaScript reserved word or global (`if`, `var`, `function`, ...).  The
% prefix is applied uniformly to definitions and references, so they match.
identifier(Name) -->
  "$", chars(Name).

% Emit a list of characters verbatim.
chars([]) --> [].
chars([Char | Chars]) -->
  [Char],
  chars(Chars).

% Unary operator spellings.
unary_operator(number_negation) --> "-".
unary_operator(boolean_negation) --> "!".
unary_operator(bit_invertion) --> "~".

% Binary operator spellings.  Note the semantic choices that match the type
% checker: `==`/`!=` become strict `===`/`!==`; the logical operators `& ^ |`
% are boolean (`&&`, boolean xor via `!==`, `||`); shifts stay numeric.
binary_operator(multiplication) --> "*".
binary_operator(division) --> "/".
binary_operator(addition) --> "+".
binary_operator(subtraction) --> "-".
binary_operator(left_bit_shift) --> "<<".
binary_operator(right_bit_shift) --> ">>".
binary_operator(less_than) --> "<".
binary_operator(less_than_or_equal) --> "<=".
binary_operator(greater_than) --> ">".
binary_operator(greater_than_or_equal) --> ">=".
binary_operator(equal) --> "===".
binary_operator(not_equal) --> "!==".
binary_operator(and) --> "&&".
binary_operator(or) --> "||".
binary_operator(xor) --> "!==".
