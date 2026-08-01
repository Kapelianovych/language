; Syntax highlighting for SL.
;
; Capture names follow the conventions most editors (Zed, Neovim, Helix)
; already ship a theme for -- see https://zed.dev/docs/extensions/languages
; ("Syntax Highlighting"). Where the grammar can't tell two roles apart
; (e.g. a bare identifier in pattern position could be a constructor or a
; binding -- see grammar.js's `conflicts` comments), this file picks the
; more common/useful reading rather than leaving it unhighlighted.
;
; ORDERING MATTERS: when two patterns below match the SAME node, the LATER
; one in this file wins (standard tree-sitter highlight-query convention --
; same as every other real grammar's highlights.scm). So generic fallbacks
; come FIRST, and increasingly specific overrides come AFTER them.

; ---------------------------------------------------------------------------
; Fallback (lowest priority -- everything else below overrides this)
; ---------------------------------------------------------------------------

(identifier) @variable

; ---------------------------------------------------------------------------
; Literals
; ---------------------------------------------------------------------------

(comment) @comment
(number) @number
(boolean) @boolean
(string_literal) @string
(js_string) @string
(wildcard) @variable.builtin

; String interpolation delimiters read as punctuation, not string content.
(interpolation
  "{" @punctuation.special
  "}" @punctuation.special)

; ---------------------------------------------------------------------------
; Keywords
; ---------------------------------------------------------------------------

[
  "use"
  "public"
  "external"
  "module"
  "opaque"
  "macro"
  "type"
  "mutable"
  "match"
  "if"
  "else"
  "from"
] @keyword

"@" @keyword.directive
"`" @keyword.directive
"~" @keyword.directive

; ---------------------------------------------------------------------------
; Operators / punctuation
; ---------------------------------------------------------------------------

[
  "="
  "=="
  "!="
  "<="
  ">="
  "+"
  "-"
  "*"
  "/"
  "&"
  "&&"
  "|"
  "||"
  "^"
  "^^"
  "!"
  "!!"
  "->"
  "<<"
  ">>"
  ".."
] @operator

[
  "("
  ")"
  "{"
  "}"
  "<"
  ">"
] @punctuation.bracket

[
  "."
  ":"
] @punctuation.delimiter

; ---------------------------------------------------------------------------
; Definitions: a name bound by `Name = value` is a function if its value is
; one, a field if the definition is itself a record's labeled member (`(x =
; 1)`; see grammar.js's `record_member`/`definition` merge note), otherwise a
; plain variable (already covered by the fallback above).
; ---------------------------------------------------------------------------

(record_member
  (definition name: (identifier) @property))

(definition
  name: (identifier) @function
  value: (function))

(destructuring pattern: (irrefutable_record_pattern) @variable)

(parameter pattern: (identifier) @variable.parameter)
(parameter pattern: (irrefutable_record_pattern
  (identifier) @variable.parameter))

; A bare identifier used as the callee right before `(` reads as a call.
(postfix_expression
  . (identifier) @function
  . (call))

; ---------------------------------------------------------------------------
; Types
; ---------------------------------------------------------------------------

(type_declaration name: (identifier) @type)
(type_parameter name: (identifier) @type.parameter)
(interface_member name: (identifier) @property)
(type_member label: (identifier) @property)
(type_reference name: (qualified_name (identifier) @type))

; ---------------------------------------------------------------------------
; Modules
; ---------------------------------------------------------------------------

(module name: (identifier) @namespace)

; ---------------------------------------------------------------------------
; Constructors / patterns
; ---------------------------------------------------------------------------

(constructor name: (identifier) @constructor)
(constructor_pattern name: (qualified_name (identifier) @constructor))
(record_pattern label: (identifier) @property)

; ---------------------------------------------------------------------------
; Externals, macros, member access
; ---------------------------------------------------------------------------

(external name: (identifier) @function)
(macro_definition name: (identifier) @function.macro)
(macro_invocation name: (qualified_name (identifier) @function.macro))

; `x.name` -- read the accessed member as a field/property (a call on it,
; `x.name(...)`, would more precisely be a method, but the grammar doesn't
; carry that distinction on the access node itself -- see
; source/syntax/semantic_tokens.pl's own identical, documented imprecision).
(access member: (accessor (identifier) @property))
