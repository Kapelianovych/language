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
    function_node(Tp,Ps,Ra,B) curried arrow        ($a => $b => <B>)
    function_call_node(T,A) curried application    ($f)($a)($b)
    tuple_node(Ms)          object literal         {0: e0, "bar": e1}
    access_node(T, Acc)     bracket indexing       ($t)["bar"] / ($t)[0]
    assignment_node(A, V)   assignment expression  (($t)["bar"] = <V>)
    block_node(Es)          IIFE returning last    (() => { ...; return e })()
    definition_node(I,Ann,V) const binding         const $i = <V>;
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
:- use_module(library(lists)).

% A whole program is a newline-separated sequence of top-level statements.
% Top-level definitions become `const` bindings; any other expression becomes
% an expression statement.  (The program is module-level code, so the value
% of the final expression is not returned anywhere.)
program(program_node(Expressions)) -->
  statements(Expressions).

statements([]) --> [].
% An import becomes an ES-module `import { ... }`.  The loader has already
% rewritten each `use` into an `import_node` carrying the JavaScript specifier
% and only the RUNTIME names (values and constructors); type-only imports were
% dropped, so the name list is never empty here.
statements([import_node(JsPath, Names) | Expressions]) -->
  "import { ", import_specifiers(Names), " } from \"", chars(JsPath), "\";\n",
  statements(Expressions).
% A whole-module import: each `Foreign - Local` pair becomes a renamed
% specifier `$Foreign as $Local`, so a namespaced member `Math.add` (the local
% `$Math$add`) binds to the dependency's export `$add`.
statements([namespace_import_node(JsPath, Renames) | Expressions]) -->
  "import { ", renamed_specifiers(Renames), " } from \"", chars(JsPath), "\";\n",
  statements(Expressions).
% A foreign (`external`) declaration: bind the name to its JavaScript source,
% wrapping a function source in a currying shim (see external_definition//3).
statements([external_node(Name, Type, Source) | Expressions]) -->
  external_definition(Name, Type, Source),
  statements(Expressions).
% A tagged-union declaration emits one `const` per constructor (a curried
% function building a tagged object, or a value for a nullary constructor).
statements([type_declaration_node(_, _, _, variant_body(Constructors)) | Expressions]) -->
  constructor_definitions(Constructors),
  statements(Expressions).
% Other type declarations (aliases / opaque) are compile-time only.
statements([type_declaration_node(_, _, _, _) | Expressions]) -->
  statements(Expressions).
% A `public` tagged union exports each of its constructors.
statements([public_node(type_declaration_node(_, _, _, variant_body(Constructors))) | Expressions]) -->
  exported_constructor_definitions(Constructors),
  statements(Expressions).
% A `public` alias / opaque type is compile-time only, like its private form.
statements([public_node(type_declaration_node(_, _, _, _)) | Expressions]) -->
  statements(Expressions).
% A `public` definition becomes an exported `const`.
statements([public_node(definition_node(Identifier, Annotation, Value)) | Expressions]) -->
  "export ",
  statement(definition_node(Identifier, Annotation, Value)),
  "\n",
  statements(Expressions).
% A `public external` becomes an exported foreign binding.
statements([public_node(external_node(Name, Type, Source)) | Expressions]) -->
  exported_external_definition(Name, Type, Source),
  statements(Expressions).
statements([Expression | Expressions]) -->
  statement(Expression),
  "\n",
  statements(Expressions).

% Comma-separated `$`-mangled import names.
import_specifiers([Name]) -->
  identifier(Name).
import_specifiers([Name, Next | Rest]) -->
  identifier(Name),
  ", ",
  import_specifiers([Next | Rest]).

% Comma-separated `$Foreign as $Local` renamed specifiers.
renamed_specifiers([Foreign - Local]) -->
  identifier(Foreign), " as ", identifier(Local).
renamed_specifiers([Foreign - Local, Next | Rest]) -->
  identifier(Foreign), " as ", identifier(Local), ", ",
  renamed_specifiers([Next | Rest]).

% A statement is either a `const` binding (for a definition) or an expression
% terminated by a semicolon.  The clauses are mutually exclusive: the last is
% guarded so it never matches a definition or a (code-free) type declaration.
statement(definition_node(identifier_node(Name), _Annotation, Value)) -->
  "const ", identifier(Name), " = ", expression(Value), ";".
statement(type_declaration_node(_, _, _, _)) --> [].
% A destructuring definition becomes a `const` with a JS destructuring target.
statement(destructuring_node(Pattern, Value)) -->
  "const ", js_pattern(Pattern, 0, _), " = ", expression(Value), ";".
statement(Expression) -->
  { Expression \= definition_node(_, _, _),
    Expression \= type_declaration_node(_, _, _, _),
    Expression \= destructuring_node(_, _) },
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
% Type annotations carry no runtime meaning and are dropped here.
expression(function_node(_TypeParameters, [], _ReturnAnnotation, Body)) -->
  "(() => ", arrow_body(Body), ")".
expression(function_node(_TypeParameters, [Parameter | Parameters], _ReturnAnnotation, Body)) -->
  "(", curried_arrows([Parameter | Parameters], Body), ")".

% Application -> curried call: the callee, then one parenthesised argument per
% argument.  A zero-argument call is emitted as `callee()`.
expression(function_call_node(Target, Arguments)) -->
  { \+ member(placeholder_node, Arguments) },
  "(", expression(Target), ")", call_arguments(Arguments).
% A call with placeholders -> a curried arrow over the holes (in order) whose
% body applies the callee with the holes filled in:
%   foo(_ 'x')  ->  ($_h0 => (foo)($_h0)(`x`))
expression(function_call_node(Target, Arguments)) -->
  { member(placeholder_node, Arguments) },
  "(", hole_arrows(Arguments, 0, _),
  "(", expression(Target), ")", section_arguments(Arguments, 0, _),
  ")".

% Tuple -> object literal.  Positional members get sequential numeric keys
% (0, 1, ... in positional order, skipping labeled members), labeled members
% get their name as a string key.  The empty tuple () is the unit value {}.
% Mutability is a compile-time-only concept and is not reflected at runtime.
expression(tuple_node(Members)) -->
  "{", object_body(Members), "}".

% Member access -> bracket indexing, so numeric and unicode-label keys work
% uniformly: foo.bar -> (foo)["bar"], foo.0 -> (foo)[0].
expression(access_node(Target, label(Name))) -->
  "(", expression(Target), ")[\"", chars(Name), "\"]".
expression(access_node(Target, index(Index))) -->
  "(", expression(Target), ")[", number(Index), "]".

% Member assignment -> a JavaScript assignment expression.
expression(assignment_node(Access, Value)) -->
  "(", expression(Access), " = ", expression(Value), ")".

% Block -> an immediately-invoked arrow function that runs the inner
% statements and returns the value of the last expression.
expression(block_node(Expressions)) -->
  "(() => { ", block_body(Expressions), " })()".

% Match -> an IIFE binding the scrutinee to `$_match`, then a chain of
% arms.  Each arm binds its pattern's variables, tests its literal
% sub-patterns (and guard), and returns its result on a match.  Type-checking
% guarantees the record shape, so only literals and guards are tested at
% runtime.  (`$_match` cannot collide: user names never begin with `$_`.)
expression(match_node(Scrutinee, RawArms)) -->
  { desugar_arms(RawArms, Arms) },
  "(($_match) => { ",
  match_arms(Arms),
  "throw new Error(\"non-exhaustive match\"); })(",
  expression(Scrutinee),
  ")".

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
expression(definition_node(_Target, _Annotation, Value)) -->
  expression(Value).

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

% Curried arrow chain: `$p1 => $p2 => ... => <body>`.
curried_arrows([Parameter], Body) -->
  parameter(Parameter), " => ", arrow_body(Body).
curried_arrows([Parameter, Next | Parameters], Body) -->
  parameter(Parameter), " => ", curried_arrows([Next | Parameters], Body).

% An arrow-function body.  A tuple compiles to an object literal `{...}`, but
% `=> {` after an arrow opens a STATEMENT BLOCK, not an object, so a tuple body
% must be wrapped in parentheses: `=> ({...})`.  No other expression begins
% with `{`, so only tuples need this.
arrow_body(tuple_node(Members)) -->
  "(", expression(tuple_node(Members)), ")".
arrow_body(Body) -->
  { Body \= tuple_node(_) },
  expression(Body).

% A parameter is rendered as its JS binding pattern (parenthesised so a
% destructuring pattern is a valid arrow-function parameter).
parameter(parameter_node(Pattern, _Annotation)) -->
  "(", js_pattern(Pattern, 0, _), ")".

% A pattern as a JS binding target.  `Counter` numbers anonymous holes
% (wildcards / ignored literals) so they get distinct throwaway names.
js_pattern(binding_pattern(Name), Counter, Counter) -->
  "$", chars(Name).
js_pattern(wildcard_pattern, CounterIn, CounterOut) -->
  "$_", number(CounterIn), { CounterOut is CounterIn + 1 }.
js_pattern(literal_pattern(_), CounterIn, CounterOut) -->
  "$_", number(CounterIn), { CounterOut is CounterIn + 1 }.
js_pattern(record_pattern(Members), CounterIn, CounterOut) -->
  "{", js_pattern_members(Members, 0, CounterIn, CounterOut), "}".

js_pattern_members([], _Index, Counter, Counter) --> [].
js_pattern_members([Member], Index, CounterIn, CounterOut) -->
  js_pattern_member(Member, Index, _NextIndex, CounterIn, CounterOut).
js_pattern_members([Member, Next | Members], Index, CounterIn, CounterOut) -->
  js_pattern_member(Member, Index, NextIndex, CounterIn, Counter1),
  ", ",
  js_pattern_members([Next | Members], NextIndex, Counter1, CounterOut).

js_pattern_member(positional_member_pattern(SubPattern), Index, NextIndex, CounterIn, CounterOut) -->
  number(Index), ": ", js_pattern(SubPattern, CounterIn, CounterOut),
  { NextIndex is Index + 1 }.
js_pattern_member(labeled_member_pattern(Name, SubPattern), Index, Index, CounterIn, CounterOut) -->
  "\"", chars(Name), "\": ", js_pattern(SubPattern, CounterIn, CounterOut).

% Curried application: `()` for no arguments, otherwise `(a)(b)(c)`.
call_arguments([]) --> "()".
call_arguments([Argument | Arguments]) -->
  argument_applications([Argument | Arguments]).

argument_applications([]) --> [].
argument_applications([Argument | Arguments]) -->
  "(", expression(Argument), ")", argument_applications(Arguments).

% Section codegen helpers.  `hole_arrows` emits one `$_hN => ` per
% placeholder (in order); `section_arguments` applies the callee, using the
% matching `$_hN` for each placeholder and the expression for each real
% argument.  Hole numbering matches between the two passes.
hole_arrows([], Counter, Counter) --> [].
hole_arrows([placeholder_node | Arguments], CounterIn, CounterOut) -->
  "$_h", number(CounterIn), " => ",
  { Counter1 is CounterIn + 1 },
  hole_arrows(Arguments, Counter1, CounterOut).
hole_arrows([Argument | Arguments], CounterIn, CounterOut) -->
  { Argument \= placeholder_node },
  hole_arrows(Arguments, CounterIn, CounterOut).

section_arguments([], Counter, Counter) --> [].
section_arguments([placeholder_node | Arguments], CounterIn, CounterOut) -->
  "($_h", number(CounterIn), ")",
  { Counter1 is CounterIn + 1 },
  section_arguments(Arguments, Counter1, CounterOut).
section_arguments([Argument | Arguments], CounterIn, CounterOut) -->
  { Argument \= placeholder_node },
  "(", expression(Argument), ")",
  section_arguments(Arguments, CounterIn, CounterOut).

% Body of a block IIFE: leading statements, then a `return` of the last value.
block_body([]) --> [].
block_body([Expression]) -->
  return_statement(Expression).
block_body([Expression, Next | Expressions]) -->
  statement(Expression), " ", block_body([Next | Expressions]).

% The final element of a block is what the block evaluates to.  A trailing
% definition is still bound first (so a recursive function can refer to
% itself) and then returned.
return_statement(definition_node(identifier_node(Name), _Annotation, Value)) -->
  "const ", identifier(Name), " = ", expression(Value), "; return ", identifier(Name), ";".
return_statement(type_declaration_node(_, _, _, _)) -->
  "return undefined;".
% A trailing destructuring's bindings cannot be observed, so it just yields
% the matched value.
return_statement(destructuring_node(_Pattern, Value)) -->
  "return ", expression(Value), ";".
return_statement(Expression) -->
  { Expression \= definition_node(_, _, _),
    Expression \= type_declaration_node(_, _, _, _),
    Expression \= destructuring_node(_, _) },
  "return ", expression(Expression), ";".

% A tuple object: spreads first, then explicit `key: value` entries, so that
% an explicit field overrides a spread field of the same key (matching the
% type, where explicit fields are the record's head).  Positional members get
% sequential numeric keys; labeled members get their name as a string key.
object_body(Members) -->
  { separate_members(Members, Spreads, Regulars) },
  spread_entries(Spreads, 0, AfterSpreads),
  regular_entries(Regulars, 0, AfterSpreads, _).

separate_members([], [], []).
separate_members([spread_member(Value) | Members], [Value | Spreads], Regulars) :-
  separate_members(Members, Spreads, Regulars).
separate_members([tuple_member(Mutability, Label, Annotation, Value) | Members], Spreads,
                 [tuple_member(Mutability, Label, Annotation, Value) | Regulars]) :-
  separate_members(Members, Spreads, Regulars).

% `Count` is the number of entries emitted so far, used to place commas.
spread_entries([], Count, Count) --> [].
spread_entries([Value | Values], CountIn, CountOut) -->
  comma_if(CountIn), "...", expression(Value),
  { Count1 is CountIn + 1 },
  spread_entries(Values, Count1, CountOut).

regular_entries([], _Index, Count, Count) --> [].
regular_entries([Member | Members], Index, CountIn, CountOut) -->
  comma_if(CountIn), regular_entry(Member, Index, NextIndex),
  { Count1 is CountIn + 1 },
  regular_entries(Members, NextIndex, Count1, CountOut).

comma_if(0) --> [].
comma_if(Count) --> { Count > 0 }, ", ".

regular_entry(tuple_member(_Mutability, positional, _Annotation, Value), Index, NextIndex) -->
  number(Index), ": ", expression(Value),
  { NextIndex is Index + 1 }.
regular_entry(tuple_member(_Mutability, labeled(Name), _Annotation, Value), Index, Index) -->
  "\"", chars(Name), "\": ", expression(Value).

% Emit an integer literal.
number(Number) -->
  { number_chars(Number, Chars) },
  chars(Chars).

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
%
% A QUALIFIED name from a nested module (`Math.add`, produced by
% `module_expander.pl`) carries `.` separators, which are not legal in a JS
% identifier; each is translated to a further `$` (`$Math$add`).  Source
% identifiers are XID and so contain neither `.` nor `$`, which keeps both the
% prefix and the translated separators collision-free, and leaves ordinary
% (dot-free) names emitted exactly as before.
identifier(Name) -->
  "$", dollar_separated(Name).

dollar_separated([]) --> [].
dollar_separated(['.' | Characters]) -->
  "$",
  dollar_separated(Characters).
dollar_separated([Character | Characters]) -->
  { Character \== ('.') },
  [Character],
  dollar_separated(Characters).

% Emit a list of characters verbatim.
chars([]) --> [].
chars([Char | Chars]) -->
  [Char],
  chars(Chars).

% ---------------------------------------------------------------------------
% Match: arms, per-pattern binding declarations and runtime tests
% ---------------------------------------------------------------------------

% An or-pattern arm desugars to one single-pattern arm per alternative,
% sharing the guard and result.
desugar_arms([], []).
desugar_arms([match_arm(Patterns, Guard, Result) | Rest], Arms) :-
  desugar_alternatives(Patterns, Guard, Result, ArmsHead),
  desugar_arms(Rest, ArmsTail),
  append(ArmsHead, ArmsTail, Arms).

desugar_alternatives([], _Guard, _Result, []).
desugar_alternatives([Pattern | Patterns], Guard, Result, [match_arm(Pattern, Guard, Result) | Rest]) :-
  desugar_alternatives(Patterns, Guard, Result, Rest).

match_arms([]) --> [].
match_arms([match_arm(Pattern, Guard, Result) | Arms]) -->
  "{ ",
  pattern_bindings(Pattern, "$_match"),
  "if (",
  pattern_test(Pattern, "$_match"),
  guard_test(Guard),
  ") { return ", expression(Result), "; } } ",
  match_arms(Arms).

guard_test(no_guard) --> [].
guard_test(guard(Expression)) -->
  " && (", expression(Expression), ")".

% A constructor `C(t1..tn)` becomes a curried function building a tagged
% object: `const $C = $_c0 => .. => ({"$tag": "C", 0: $_c0, ..});`.  A nullary
% constructor is just the tagged object value.
constructor_definitions([]) --> [].
constructor_definitions([Constructor | Constructors]) -->
  one_constructor_definition(Constructor),
  constructor_definitions(Constructors).

% As above, but each `const` is `export`ed (for a `public` tagged union).
exported_constructor_definitions([]) --> [].
exported_constructor_definitions([Constructor | Constructors]) -->
  "export ",
  one_constructor_definition(Constructor),
  exported_constructor_definitions(Constructors).

% The binding name is `$`-prefixed and dot-mangled (a qualified constructor
% from a module, e.g. `Opt.Some`, becomes `$Opt$Some`), but the runtime `$tag`
% keeps the dotted qualified name verbatim (a string, where `.` is fine, and
% kept distinct so sibling modules' same-named constructors don't clash).
one_constructor_definition(constructor(Name, FieldTypes)) -->
  { length(FieldTypes, Arity) },
  "const ", identifier(Name), " = ", constructor_arrows(Name, Arity, 0), ";\n".

% ---------------------------------------------------------------------------
% Foreign (`external`) bindings
% ---------------------------------------------------------------------------

% Emit the JavaScript for one `external` declaration: the ES `import` it needs
% (if any), then a `const $Name = <marshalled value>;`.  `exported_*` is the
% same with an `export` prefix, for a `public external`.
external_definition(Name, Type, Source) -->
  external_import(Source, Name),
  { external_callee(Source, Name, Callee) },
  external_binding(Name, Type, Callee).

exported_external_definition(Name, Type, Source) -->
  external_import(Source, Name),
  { external_callee(Source, Name, Callee) },
  "export ",
  external_binding(Name, Type, Callee).

% The `import` line a source needs (none for an ambient global or a plain JS
% expression).
external_import(js_global, _Name) --> [].
external_import(js_expression(_Js), _Name) --> [].
external_import(js_module(Module, default), Name) -->
  "import { ", chars(Name), " } from \"", escaped_double_quoted(Module), "\";\n".
external_import(js_module(Module, named(Foreign)), _Name) -->
  "import { ", chars(Foreign), " } from \"", escaped_double_quoted(Module), "\";\n".

% Escape a char list for a double-quoted JS string literal: backslash (92),
% double-quote (34) and the four JavaScript line terminators -- LF (10), CR
% (13), LINE SEPARATOR (2028) and PARAGRAPH SEPARATOR (2029) -- which would
% otherwise break the string.  2028/2029 keep their codepoint via `\uXXXX`.
escaped_double_quoted([]) --> [].
escaped_double_quoted([Char | Chars]) -->
  escaped_dq_char(Char),
  escaped_double_quoted(Chars).

escaped_dq_char(Char) --> { char_code(Char, 92) }, "\\\\".
escaped_dq_char(Char) --> { char_code(Char, 34) }, "\\\"".
escaped_dq_char(Char) --> { char_code(Char, 10) }, "\\n".
escaped_dq_char(Char) --> { char_code(Char, 13) }, "\\r".
escaped_dq_char(Char) --> { char_code(Char, 0x2028) }, "\\u2028".
escaped_dq_char(Char) --> { char_code(Char, 0x2029) }, "\\u2029".
escaped_dq_char(Char) -->
  { char_code(Char, Code), \+ member(Code, [92, 34, 10, 13, 0x2028, 0x2029]) },
  [Char].

% The JS expression text the binding wraps: the declared name itself (for an
% ambient global or a same-name module import), the literal expression, or the
% renamed foreign name.
external_callee(js_global, Name, Name).
external_callee(js_expression(Js), _Name, Js).
external_callee(js_module(_Module, default), Name, Name).
external_callee(js_module(_Module, named(Foreign)), _Name, Foreign).

% `const $Name = <marshalled Callee>;`.  `from_js/5` builds the marshalled
% value: identity for data, a curry shim for functions (see below).
external_binding(Name, Type, Callee) -->
  { from_js(Type, Callee, Body, 0, _Next) },
  "const ", identifier(Name), " = ", chars(Body), ";\n".

% --- Type-directed boundary marshalling -----------------------------------
%
% A value's declared `Type` drives how it crosses the JS boundary.  Only
% FUNCTION types are adapted (the language curries, JS does not); every other
% type -- numbers, strings, records, tuples, variants -- crosses AS-IS.
% Marshalling is bidirectional and flips at each arrow (a function's arguments
% travel the opposite way to the function itself):
%
%   from_js : wrap a JS value so the LANGUAGE can use it
%             (a function becomes curried; its arguments are sent back out
%              via to_js, its result brought in via from_js)
%   to_js   : wrap a LANGUAGE value so JS can use it
%             (a curried function becomes an uncurried JS function; its
%              arguments are brought in via from_js, its result sent out via to_js)
%
% This is why a curried callback handed to a JS higher-order function is
% correctly presented to JS as an uncurried function.  `ValueChars` is the JS
% expression text being wrapped; `N` threads a counter for fresh, capture-free
% parameter names.

% from_js(+Type, +ValueChars, -ResultChars, +N0, -N).
from_js(Type, Value, Result, N0, N) :-
  ( function_form(Type, Parameters, Return) ->
      Level = N0,
      N1 is N0 + 1,
      parameter_names(Level, 0, Parameters, Names),
      jsify_arguments(Parameters, Names, JsArguments, N1, N2),
      append_all(["(", Value, ")(", JsArguments, ")"], Application),
      from_js(Return, Application, ReturnResult, N2, N),
      curried_arrow(Names, ReturnResult, Result)
  ; Result = Value, N = N0
  ).

% to_js(+Type, +ValueChars, -ResultChars, +N0, -N).
to_js(Type, Value, Result, N0, N) :-
  ( function_form(Type, Parameters, Return) ->
      Level = N0,
      N1 is N0 + 1,
      parameter_names(Level, 0, Parameters, Names),
      languagify_application(Value, Parameters, Names, Applied, N1, N2),
      to_js(Return, Applied, ReturnResult, N2, N),
      uncurried_arrow(Names, ReturnResult, Result)
  ; Result = Value, N = N0
  ).

% A function type (looking through a leading quantifier `<A ..>`); fails for
% any non-function type, which is what keeps data crossing as-is.
function_form(quantified_type_node(_Parameters, Body), Parameters, Return) :- !,
  function_form(Body, Parameters, Return).
function_form(function_type_node(Parameters, Return), Parameters, Return).

% Fresh shim parameter names `$_a<Level>_<Index>`, one per parameter type.
parameter_names(_Level, _Index, [], []).
parameter_names(Level, Index, [_Parameter | Parameters], [Name | Names]) :-
  parameter_name(Level, Index, Name),
  Index1 is Index + 1,
  parameter_names(Level, Index1, Parameters, Names).

parameter_name(Level, Index, Name) :-
  number_chars(Level, LevelChars),
  number_chars(Index, IndexChars),
  append_all(["$_a", LevelChars, "_", IndexChars], Name).

% `to_js` each shim parameter as its declared type, comma-joined -- the
% arguments of a JS function we are wrapping for the language must leave again
% as JS values.
jsify_arguments(Parameters, Names, JsArguments, N0, N) :-
  jsify_list(Parameters, Names, Converted, N0, N),
  intercalate(", ", Converted, JsArguments).

jsify_list([], [], [], N, N).
jsify_list([Parameter | Parameters], [Name | Names], [Converted | Rest], N0, N) :-
  to_js(Parameter, Name, Converted, N0, N1),
  jsify_list(Parameters, Names, Rest, N1, N).

% Apply a curried language function `Value` to each shim parameter, bringing
% each one in via `from_js` first: `(Value)(from_js p0)(from_js p1)..`.  A
% nullary function is applied with `()`.
languagify_application(Value, [], [], Applied, N, N) :- !,
  append_all(["(", Value, ")()"], Applied).
languagify_application(Value, Parameters, Names, Applied, N0, N) :-
  append_all(["(", Value, ")"], Base),
  languagify_apply(Base, Parameters, Names, Applied, N0, N).

languagify_apply(Accumulator, [], [], Accumulator, N, N).
languagify_apply(Accumulator, [Parameter | Parameters], [Name | Names], Applied, N0, N) :-
  from_js(Parameter, Name, Converted, N0, N1),
  append_all([Accumulator, "(", Converted, ")"], Accumulator1),
  languagify_apply(Accumulator1, Parameters, Names, Applied, N1, N).

% `a => b => .. => Body` (curried); nullary is `() => Body`.
curried_arrow([], Body, Result) :-
  append_all(["() => ", Body], Result).
curried_arrow([Name], Body, Result) :-
  append_all([Name, " => ", Body], Result).
curried_arrow([Name, Next | Rest], Body, Result) :-
  curried_arrow([Next | Rest], Body, Inner),
  append_all([Name, " => ", Inner], Result).

% `(a, b, ..) => Body` (uncurried JS function); nullary is `() => Body`.
uncurried_arrow(Names, Body, Result) :-
  intercalate(", ", Names, ParameterList),
  append_all(["(", ParameterList, ") => ", Body], Result).

% Join character-lists with a separator.
intercalate(_Separator, [], []).
intercalate(_Separator, [X], X) :- !.
intercalate(Separator, [X, Y | Rest], Result) :-
  intercalate(Separator, [Y | Rest], Joined),
  append_all([X, Separator, Joined], Result).

append_all([], []).
append_all([Chars | Rest], Result) :-
  append_all(Rest, RestResult),
  append(Chars, RestResult, Result).

constructor_arrows(Name, Arity, Index) -->
  { Index < Arity },
  "$_c", number(Index), " => ",
  { Index1 is Index + 1 },
  constructor_arrows(Name, Arity, Index1).
constructor_arrows(Name, Arity, Arity) -->
  "({\"$tag\": \"", chars(Name), "\"", constructor_object_fields(0, Arity), "})".

constructor_object_fields(Arity, Arity) --> [].
constructor_object_fields(Index, Arity) -->
  { Index < Arity },
  ", ", number(Index), ": $_c", number(Index),
  { Index1 is Index + 1 },
  constructor_object_fields(Index1, Arity).

% `Path` is the JS expression (as characters) reaching the value the pattern
% is matched against -- `$_match`, then `[i]` / `["label"]` as we descend.

% Binding declarations: `const $name = <path>;` for each binding sub-pattern.
pattern_bindings(wildcard_pattern, _Path) --> [].
pattern_bindings(literal_pattern(_), _Path) --> [].
pattern_bindings(binding_pattern(Name), Path) -->
  "const $", chars(Name), " = ", chars(Path), "; ".
pattern_bindings(record_pattern(Members), Path) -->
  record_pattern_bindings(Members, 0, Path).
pattern_bindings(constructor_pattern(_Name, SubPatterns), Path) -->
  constructor_sub_bindings(SubPatterns, 0, Path).

constructor_sub_bindings([], _Index, _Path) --> [].
constructor_sub_bindings([SubPattern | SubPatterns], Index, Path) -->
  { index_path(Path, Index, SubPath), Index1 is Index + 1 },
  pattern_bindings(SubPattern, SubPath),
  constructor_sub_bindings(SubPatterns, Index1, Path).

record_pattern_bindings([], _Index, _Path) --> [].
record_pattern_bindings([positional_member_pattern(SubPattern) | Members], Index, Path) -->
  { index_path(Path, Index, SubPath), Index1 is Index + 1 },
  pattern_bindings(SubPattern, SubPath),
  record_pattern_bindings(Members, Index1, Path).
record_pattern_bindings([labeled_member_pattern(Name, SubPattern) | Members], Index, Path) -->
  { label_path(Path, Name, SubPath) },
  pattern_bindings(SubPattern, SubPath),
  record_pattern_bindings(Members, Index, Path).

% Runtime test: `true`, conjoined with an equality check for each literal
% sub-pattern.  Bindings and wildcards impose no runtime test (the type
% checker guarantees the shape).
pattern_test(Pattern, Path) -->
  "true",
  pattern_conjuncts(Pattern, Path).

pattern_conjuncts(wildcard_pattern, _Path) --> [].
pattern_conjuncts(binding_pattern(_), _Path) --> [].
pattern_conjuncts(literal_pattern(Node), Path) -->
  " && (", chars(Path), " === ", literal_value(Node), ")".
pattern_conjuncts(record_pattern(Members), Path) -->
  record_pattern_conjuncts(Members, 0, Path).
pattern_conjuncts(constructor_pattern(Name, SubPatterns), Path) -->
  " && (", chars(Path), "[\"$tag\"] === \"", chars(Name), "\")",
  constructor_sub_conjuncts(SubPatterns, 0, Path).

constructor_sub_conjuncts([], _Index, _Path) --> [].
constructor_sub_conjuncts([SubPattern | SubPatterns], Index, Path) -->
  { index_path(Path, Index, SubPath), Index1 is Index + 1 },
  pattern_conjuncts(SubPattern, SubPath),
  constructor_sub_conjuncts(SubPatterns, Index1, Path).

record_pattern_conjuncts([], _Index, _Path) --> [].
record_pattern_conjuncts([positional_member_pattern(SubPattern) | Members], Index, Path) -->
  { index_path(Path, Index, SubPath), Index1 is Index + 1 },
  pattern_conjuncts(SubPattern, SubPath),
  record_pattern_conjuncts(Members, Index1, Path).
record_pattern_conjuncts([labeled_member_pattern(Name, SubPattern) | Members], Index, Path) -->
  { label_path(Path, Name, SubPath) },
  pattern_conjuncts(SubPattern, SubPath),
  record_pattern_conjuncts(Members, Index, Path).

literal_value(number_node(Number)) --> number(Number).
literal_value(boolean_node(true)) --> "true".
literal_value(boolean_node(false)) --> "false".
literal_value(string_node(Parts)) --> "`", template_parts(Parts), "`".

% Build the JS path for a positional / labeled sub-field.
index_path(Path, Index, SubPath) :-
  number_chars(Index, IndexChars),
  append(Path, ['[' | IndexChars], Partial),
  append(Partial, [']'], SubPath).
label_path(Path, Name, SubPath) :-
  append(Path, ['[', '"' | Name], Partial),
  append(Partial, ['"', ']'], SubPath).

% Unary operator spellings.
unary_operator(number_negation) --> "-".
unary_operator(boolean_negation) --> "!".
unary_operator(bit_invertion) --> "~".

% Binary operator spellings.  Note the semantic choices that match the type
% checker: `==`/`!=` become strict `===`/`!==`; the BITWISE operators (source
% `&& ^^ ||`, on numbers) map to JS's single-character `& ^ |`; the BOOLEAN
% operators (source `& ^ |`, on booleans) map to `&&`, boolean xor via `!==`,
% and `||`; shifts stay numeric.
binary_operator(multiplication) --> "*".
binary_operator(division) --> "/".
binary_operator(addition) --> "+".
binary_operator(subtraction) --> "-".
binary_operator(left_bit_shift) --> "<<".
binary_operator(right_bit_shift) --> ">>".
binary_operator(bitwise_and) --> "&".
binary_operator(bitwise_xor) --> "^".
binary_operator(bitwise_or) --> "|".
binary_operator(less_than) --> "<".
binary_operator(less_than_or_equal) --> "<=".
binary_operator(greater_than) --> ">".
binary_operator(greater_than_or_equal) --> ">=".
binary_operator(equal) --> "===".
binary_operator(not_equal) --> "!==".
binary_operator(and) --> "&&".
binary_operator(or) --> "||".
binary_operator(xor) --> "!==".
