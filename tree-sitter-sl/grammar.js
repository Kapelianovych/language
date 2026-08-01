// Tree-sitter grammar for SL, translated from the authoritative PEG-style
// spec at ../grammar (cross-checked against source/syntax/lexer.pl
// and source/syntax/parser.pl, the actual hand-written scannerless parser).
// This grammar targets EDITOR use (highlighting, folding, indentation) --
// not a validating parser -- so it favors permissiveness at a few spots the
// real parser is stricter about (see comments below).

const PREC = {
  PIPE: 1, // ->
  BOOL_OR: 2, // |
  BOOL_XOR: 3, // ^
  BOOL_AND: 4, // &
  EQUALITY: 5, // == !=
  COMPARE: 6, // < <= > >=
  BIT_OR: 7, // ||
  BIT_XOR: 8, // ^^
  BIT_AND: 9, // &&
  SHIFT: 10, // << >>
  ADD: 11, // + -
  MUL: 12, // * /
  UNARY: 13, // - ! !!
  CALL: 14, // postfix . () and the type-argument-call reading of `<...>(`
};

// [operator, precedence] for every binary operator, shared between the full
// `binary_expression` and the `|`-excluding `restricted_binary_expression`
// (see the latter's comment).
const BINARY_OPERATORS = [
  ['*', PREC.MUL],
  ['/', PREC.MUL],
  ['+', PREC.ADD],
  ['-', PREC.ADD],
  ['<<', PREC.SHIFT],
  ['>>', PREC.SHIFT],
  ['&&', PREC.BIT_AND],
  ['^^', PREC.BIT_XOR],
  ['||', PREC.BIT_OR],
  ['<=', PREC.COMPARE],
  ['<', PREC.COMPARE],
  ['>=', PREC.COMPARE],
  ['>', PREC.COMPARE],
  ['==', PREC.EQUALITY],
  ['!=', PREC.EQUALITY],
  ['&', PREC.BOOL_AND],
  ['^', PREC.BOOL_XOR],
  ['|', PREC.BOOL_OR],
  ['->', PREC.PIPE],
];

module.exports = grammar({
  name: 'sl',

  word: $ => $.identifier,

  extras: $ => [$.comment, $._whitespace],

  conflicts: $ => [
    // `(n)`, `(a b)`, `()` -- a parenthesised group of bare
    // identifiers/wildcards (or none at all) parses as both a record and a
    // parameter list; `function`'s dynamic precedence below picks the
    // function reading when a full parse exists either way, matching
    // parser.pl's `paren_or_function` ("the language resolves the ambiguity
    // in favour of the function"). Real parameter shapes narrower than a
    // bare name (labeled members, literals, spreads) don't overlap with
    // `parameter` at all, so this conflict is only ever this narrow case.
    // All stem from the SAME root ambiguity above: a parenthesised group's
    // opening `(` doesn't yet reveal whether it is a `record` (general
    // expressions/labeled members/spreads) or a `function`'s parameter list
    // (identifiers/wildcards/nested irrefutable patterns only) until the
    // members' actual shapes -- or what follows the closing `)` -- are
    // known. GLR explores every reading; `function`'s dynamic precedence
    // above picks it when a full parse survives that way.
    [$.record, $.function],
    [$._irrefutable_pattern, $.definition],
    [$._irrefutable_pattern, $._primary_expression],
    [$.irrefutable_record_pattern, $.record],
    [$.parameter, $._irrefutable_pattern_member],
    [$.type_declaration],
    [$.function, $.irrefutable_record_pattern],
    [$.record, $.function, $.irrefutable_record_pattern],
    [$.match],
    [$.type_reference],
    // `type X = Identifier` -- a single bare name with no leading `|` and no
    // field list reads as either a nullary variant constructor or a plain
    // type alias (see grammar.md's `VariantBody` note); either reading
    // highlights identically, so which one GLR settles on doesn't matter
    // here.
    [$.constructor, $.qualified_name],
    [$.variant_body],
    [$._type_expression, $.intersection_type],
    [$.type_parameter, $._primary_expression],
    // A bare name in pattern position is only resolved to a nullary
    // constructor pattern vs. a binding by NAME RESOLUTION (is it an
    // in-scope nullary constructor?) -- see grammar.md's `ConstructorPattern`
    // note. Not decidable here; either reading highlights as a plain
    // identifier anyway.
    [$.qualified_name, $._pattern],
    [$.constructor],
    [$.constructor_pattern],
  ],

  rules: {
    // -------------------------------------------------------------------
    // Program structure
    // -------------------------------------------------------------------

    source_file: $ => repeat($._program_item),

    _program_item: $ => choice(
      $.use,
      $.public,
      $.external,
      $.module,
      $.macro_definition,
      $._expression,
    ),

    use: $ => seq(
      'use',
      field('path', $.import_path),
      optional(seq(':', field('names', $.import_names))),
    ),

    import_path: $ => token(/[^\s():#]+/),

    import_names: $ => seq('(', repeat1($.identifier), ')'),

    public: $ => seq(
      'public',
      choice($.external, $.module, $.macro_definition, $._expression),
    ),

    // -------------------------------------------------------------------
    // Modules
    // -------------------------------------------------------------------

    module: $ => seq(
      optional('opaque'),
      'module',
      field('name', $.identifier),
      optional(field('type_parameters', $.type_parameters)),
      optional(seq(':', field('ascription', $._type_expression))),
      '=',
      '{',
      repeat($._program_item),
      '}',
    ),

    // -------------------------------------------------------------------
    // External (foreign JS) bindings
    // -------------------------------------------------------------------

    external: $ => seq(
      'external',
      field('name', $.identifier),
      ':',
      field('type', $._type_expression),
      optional($.external_source),
    ),

    external_source: $ => choice(
      seq('=', field('source', $.js_string), 'from', field('module', $.js_string)),
      seq('=', field('source', $.js_string)),
      seq('from', field('module', $.js_string)),
    ),

    // Raw, unescaped, non-interpolating single-quoted string -- distinct
    // from the language's own `string_literal` (see grammar.md's `JsString`).
    js_string: $ => seq(
      "'",
      optional(token.immediate(/[^']+/)),
      "'",
    ),

    // -------------------------------------------------------------------
    // Reader macros
    // -------------------------------------------------------------------

    macro_definition: $ => seq(
      'macro',
      field('name', $.identifier),
      '=',
      '(', repeat($.identifier), ')',
      field('body', $._expression),
    ),

    macro_invocation: $ => prec(PREC.CALL, seq(
      '@',
      field('name', $.qualified_name),
      '(', optional($._call_argument_list), ')',
      field('source', $._expression),
    )),

    quote: $ => seq('`', '(', $._expression, ')'),

    unquote: $ => prec(PREC.UNARY, seq(
      '~',
      choice($.identifier, seq('(', $._expression, ')')),
    )),

    // -------------------------------------------------------------------
    // Type declarations
    // -------------------------------------------------------------------

    type_declaration: $ => seq(
      'type',
      field('name', $.identifier),
      optional(field('type_parameters', $.type_parameters)),
      optional(seq(
        '=',
        optional('opaque'),
        choice($.variant_body, $.interface_body, $._type_expression),
      )),
    ),

    variant_body: $ => seq(
      optional('|'),
      $.constructor,
      repeat(seq('|', $.constructor)),
    ),

    // Dynamic precedence: for `type X = Some(A) | None`, a bare `Some`
    // (before its `(A)` field list is even seen) is ALSO a complete
    // `qualified_name`/`type_reference` -- so `type X = Some` could end the
    // whole `type_declaration` right there, leaving `(A) | None` to parse as
    // a separate, following, perfectly-valid top-level expression. Both are
    // full parses of the file; this precedence prefers keeping the WHOLE
    // `Some(A) | None` inside one `type_declaration`, matching how a
    // variant is actually meant to read (see `[$.constructor,
    // $.qualified_name]` in `conflicts` above).
    constructor: $ => prec.dynamic(2, seq(
      field('name', $.identifier),
      optional(seq('(', sepBy1($, $._type_expression), ')')),
    )),

    interface_body: $ => seq(
      '{',
      repeat($.interface_member),
      '}',
    ),

    interface_member: $ => seq(
      field('name', $.identifier),
      ':',
      field('type', $._type_expression),
    ),

    // -------------------------------------------------------------------
    // Type parameters / arguments / expressions
    // -------------------------------------------------------------------

    type_parameters: $ => seq('<', sepBy1($, $.type_parameter), '>'),

    type_parameter: $ => seq(
      field('name', $.identifier),
      optional(choice(
        // Higher-kinded: Name<_ ... _>
        seq('<', sepBy1($, '_'), '>'),
        // Proper, optionally bounded
        seq(':', field('bound', $._type_expression)),
      )),
    ),

    _type_expression: $ => choice(
      $.intersection_type,
      $._type_expression_primary,
    ),

    intersection_type: $ => prec.left(seq(
      $._type_expression_primary,
      repeat1(seq('+', $._type_expression_primary)),
    )),

    _type_expression_primary: $ => choice(
      $.quantified_type,
      $.parenthesized_type,
      $.type_reference,
    ),

    quantified_type: $ => prec.right(seq(
      field('type_parameters', $.type_parameters),
      field('body', $._type_expression_primary),
    )),

    parenthesized_type: $ => seq(
      '(',
      optional(sepBy1($, $.type_member)),
      optional(seq('..', optional($.identifier))),
      ')',
      optional(seq(':', field('return_type', $._type_expression))),
    ),

    type_member: $ => seq(
      optional('mutable'),
      choice(
        seq(field('label', $.identifier), ':', field('type', $._type_expression)),
        $._type_expression,
      ),
    ),

    type_reference: $ => prec(1, seq(
      field('name', $.qualified_name),
      optional(field('type_arguments', $.type_arguments)),
    )),

    type_arguments: $ => seq('<', sepBy1($, $._type_argument), '>'),

    _type_argument: $ => choice('_', $._type_expression),

    qualified_name: $ => sepBy1Dot($, $.identifier),

    // -------------------------------------------------------------------
    // Blocks, records/records
    // -------------------------------------------------------------------

    block: $ => seq('{', repeat($._expression), '}'),

    record: $ => seq('(', repeat($.record_member), ')'),

    // A labeled member (`x = 1`, `x: number = 1`) is syntactically IDENTICAL
    // to a `definition` (see grammar.md: both are `Identifier
    // TypeAnnotation? "=" Expression`) -- there is deliberately no separate
    // `labeled_member` rule here competing with it for the same input; a
    // record member that looks like a definition simply IS one (`definition`
    // is already reachable via `_expression` below), same shape either way.
    record_member: $ => choice(
      $.spread,
      seq(optional('mutable'), $._expression),
    ),

    spread: $ => seq('..', $._expression),

    // -------------------------------------------------------------------
    // Functions, parameters, patterns
    // -------------------------------------------------------------------

    function: $ => prec.dynamic(1, prec.right(seq(
      optional(field('type_parameters', $.type_parameters)),
      '(', repeat($.parameter), ')',
      optional(seq(':', field('return_type', $._type_expression))),
      field('body', $._expression),
    ))),

    parameter: $ => seq(
      field('pattern', $._irrefutable_pattern),
      optional(seq(':', field('type', $._type_expression))),
    ),

    _pattern: $ => choice(
      $.constructor_pattern,
      $.record_pattern,
      $.number,
      $.boolean,
      $.string_literal,
      $.wildcard,
      $.identifier,
    ),

    wildcard: $ => '_',

    constructor_pattern: $ => prec(1, seq(
      field('name', $.qualified_name),
      optional(seq('(', sepBy($, $._pattern), ')')),
    )),

    record_pattern: $ => seq('(', repeat($._pattern_member), ')'),

    _pattern_member: $ => choice(
      seq(field('label', $.identifier), '=', field('value', $._pattern)),
      $._pattern,
    ),

    _irrefutable_pattern: $ => choice(
      $.irrefutable_record_pattern,
      $.wildcard,
      $.identifier,
    ),

    irrefutable_record_pattern: $ => seq('(', repeat($._irrefutable_pattern_member), ')'),

    _irrefutable_pattern_member: $ => choice(
      seq(field('label', $.identifier), '=', field('value', $._irrefutable_pattern)),
      $._irrefutable_pattern,
    ),

    // -------------------------------------------------------------------
    // Postfix: member access, calls, trailing assignment
    // -------------------------------------------------------------------

    _postfix_expression: $ => choice(
      $.postfix_expression,
      $._primary_expression,
    ),

    postfix_expression: $ => prec.left(PREC.CALL, seq(
      $._primary_expression,
      repeat1(choice($.access, $.call, $.type_apply)),
      optional($.assignment),
    )),

    _primary_expression: $ => choice(
      $.number,
      $.boolean,
      $.string_literal,
      $.record,
      $.block,
      $.identifier,
    ),

    access: $ => seq('.', field('member', $.accessor)),

    accessor: $ => choice($.identifier, /[0-9]+/),

    call: $ => prec.dynamic(1, seq(
      '(', optional($._call_argument_list), ')',
    )),

    // Explicit type arguments applied to a value, on their own (`Box<number>`
    // -- e.g. fixing a generic module's type parameter with nothing being
    // called) OR immediately followed by a `call` in the same postfix chain
    // (`foo<number>(1)`) -- parser.pl's `postfix_chain` handles both via the
    // same shape, deciding call-vs-standalone only by whether `(` happens to
    // follow, not as part of this rule itself. This is what keeps `a < b` a
    // plain comparison everywhere else (see `conflicts` above), and lets GLR
    // resolve `a < b > (c)` as a call with one type argument, `a < b > c`
    // (nothing special following) as standalone `a<b>` then a separate `c` --
    // both real, still-ambiguous cases documented in parser.pl, resolved the
    // same way here.
    type_apply: $ => prec.dynamic(1, $.type_arguments),

    _call_argument_list: $ => sepBy1($, $.call_argument),

    call_argument: $ => choice('_', $._expression),

    // Mutation through an access chain: `record.field = value`.
    assignment: $ => seq('=', field('value', $._expression)),

    // -------------------------------------------------------------------
    // Unary / binary operators
    // -------------------------------------------------------------------

    unary_expression: $ => prec(PREC.UNARY, seq(
      field('operator', choice('!!', '!', '-')),
      field('operand', $._expression),
    )),

    binary_expression: $ => choice(
      ...BINARY_OPERATORS.map(([op, prec_]) => prec.left(prec_, seq(
        field('left', $._expression),
        field('operator', op),
        field('right', $._expression),
      ))),
    ),

    // -------------------------------------------------------------------
    // Restricted expression: identical to `_expression`, EXCEPT the bare
    // `|` (bool-or) operator is unavailable at any unbracketed level --
    // used only for a match arm's guard/result. Per grammar.md's
    // `MatchArm`: "Inside a guard or result the binary `|` operator is
    // unavailable at the top level (a `|` there always starts the next
    // pattern/arm) ... All other operators, including the lower-precedence
    // pipe `->`, work unwrapped." So `->` (precedence 1, LOWER than `|`'s 2)
    // must still work bare, ruling out a simple "block anything below this
    // precedence" number -- hence a real parallel rule excluding just `|`
    // by identity, recursing into ITSELF (not `_expression`) so a `|`
    // can't sneak in one level down either. Any BRACKETED sub-expression
    // (a record/block/function-body/call-argument nested inside) switches
    // back to full `_expression` immediately, same as everywhere else,
    // since only THOSE rules reference `_expression`, not this one.
    // -------------------------------------------------------------------

    _match_result_expression: $ => choice(
      $.type_declaration,
      $.definition,
      $.destructuring,
      $.function,
      $.conditional,
      $.match,
      $.restricted_binary_expression,
      $.quote,
      $.unquote,
      $.macro_invocation,
      $.restricted_unary_expression,
      $._postfix_expression,
    ),

    restricted_unary_expression: $ => prec(PREC.UNARY, seq(
      field('operator', choice('!!', '!', '-')),
      field('operand', $._match_result_expression),
    )),

    restricted_binary_expression: $ => choice(
      ...BINARY_OPERATORS.filter(([op]) => op !== '|').map(([op, prec_]) => prec.left(prec_, seq(
        field('left', $._match_result_expression),
        field('operator', op),
        field('right', $._match_result_expression),
      ))),
    ),

    // -------------------------------------------------------------------
    // Definitions, destructuring, conditionals, match
    // -------------------------------------------------------------------

    definition: $ => prec.right(seq(
      field('name', $.identifier),
      optional(seq(':', field('type', $._type_expression))),
      '=',
      field('value', $._expression),
    )),

    destructuring: $ => prec.right(seq(
      field('pattern', $.irrefutable_record_pattern),
      '=',
      field('value', $._expression),
    )),

    conditional: $ => prec.right(seq(
      'if',
      field('condition', $._expression),
      field('consequence', $._expression),
      'else',
      field('alternative', $._expression),
    )),

    match: $ => seq(
      'match',
      field('scrutinee', $._postfix_expression),
      repeat1(seq('|', $.match_arm)),
    ),

    // `guard`/`result` use `_match_result_expression`, NOT `_expression` --
    // see that rule's own comment for why (grammar.md's `MatchArm` note on
    // `|` being unavailable there, since it always starts the next arm).
    match_arm: $ => prec.right(seq(
      field('pattern', $._pattern),
      repeat(seq('|', field('pattern', $._pattern))),
      optional(seq('if', field('guard', $._match_result_expression))),
      '=>',
      field('result', $._match_result_expression),
    )),

    // -------------------------------------------------------------------
    // Expression (top choice)
    // -------------------------------------------------------------------

    _expression: $ => choice(
      $.type_declaration,
      $.definition,
      $.destructuring,
      $.function,
      $.conditional,
      $.match,
      $.binary_expression,
      $.quote,
      $.unquote,
      $.macro_invocation,
      $.unary_expression,
      $._postfix_expression,
    ),

    // -------------------------------------------------------------------
    // Lexical: literals, identifiers, comments
    // -------------------------------------------------------------------

    identifier: $ => /[\p{XID_Start}_$][\p{XID_Continue}$]*/u,

    boolean: $ => choice('true', 'false'),

    number: $ => token(choice(
      /0[bB][01](,?[01])*/,
      /0[oO][0-7](,?[0-7])*/,
      /0[xX][0-9a-fA-F](,?[0-9a-fA-F])*/,
      /[0-9](,?[0-9])*(\.[0-9](,?[0-9])*)?([eE][+-]?[0-9](,?[0-9])*)?/,
    )),

    // Single-quoted, possibly interpolating: `'text {expr} more \{literal}'`.
    string_literal: $ => seq(
      "'",
      repeat(choice($._string_fragment, $.interpolation)),
      "'",
    ),

    // A run of characters that are neither the closing quote nor an
    // unescaped `{` (which would start an interpolation); `\{` is the one
    // recognised escape (a literal brace), everything else -- including a
    // lone backslash -- is ordinary text (see grammar.md's `StringLiteral`).
    _string_fragment: $ => token.immediate(prec(1, /([^'{]|\\\{)+/)),

    interpolation: $ => seq(
      token.immediate('{'),
      field('value', $._expression),
      '}',
    ),

    comment: $ => token(/#[^\n]*/),

    _whitespace: $ => /[\t\n\v\f\r\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+/,
  },
});

// sepBy1(rule): one or more `rule`, separated by mandatory whitespace/
// comments (already implicit via `extras` between any two grammar tokens --
// this just chains repeats, exactly as grammar.md's `(X (Separator+ X)*)?`
// forms do everywhere).
function sepBy1($, rule) {
  return seq(rule, repeat(rule));
}

function sepBy($, rule) {
  return optional(sepBy1($, rule));
}

// A qualified name: one or more identifiers joined by `.`, with NO
// whitespace around the dots (`Geo.Shape`, not `Geo . Shape`).
function sepBy1Dot($, rule) {
  return seq(rule, repeat(seq(token.immediate('.'), rule)));
}
