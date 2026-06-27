# Reader macros

Reader macros are the language's compile-time metaprogramming facility. A
**macro** is a function — written in the language itself — that runs *during
compilation* and turns the raw source text following its invocation into program
AST. Macros let you grow new syntax (a DSL) without changing the compiler.

```
use Compiler:(parseItem)

public macro times = (n source)
  match n
  | 0 => `(())
  | _ => {
    ast = parseItem(source)
    `(sequence(~ast ~(times(n - 1 source))))
    }

@times(3) log('tick')
```

`@times(3) log('tick')` expands, at compile time, to
`sequence(log('tick') sequence(log('tick') sequence(log('tick') ())))`, which is
then type-checked and code-generated like any ordinary program.

---

## Mental model

A macro is an ordinary function of type `(…) -> Ast`. Two things make it special:

1. It runs at **compile time** (the compiler interprets it), not at run time.
2. Its result — an `Ast` value — is **spliced into the program** in place of the
   invocation, and then compiled normally.

Everything else (parameters, `match`, recursion, blocks, arithmetic) is just the
language you already know. `Ast` and the `parseItem` primitive come from the
builtin `Compiler` module.

---

## Defining a macro

```
[public] macro NAME = ( PARAM* ) BODY
```

- `macro` is a **soft keyword** (it only takes on meaning when followed by a
  definition; a bare identifier `macro` still parses as a name).
- `PARAM*` are bare identifiers — **no type annotations**. Their types are
  *inferred* (see [Type checking](#type-checking)).
- `BODY` is an expression that must evaluate to an `Ast`.
- `public` exports the macro so other files can `use` it.
- By convention the **last parameter receives the raw `source` text** of the
  invocation, and earlier parameters receive the `( … )` arguments. The compiler
  binds parameters positionally; it does not otherwise distinguish them.

A macro is **also callable as a compile-time function** from other macro bodies —
that is how `times` recurses (`times(n - 1 source)`).

## Invoking a macro

```
@NAME( ARG* ) FOLLOWING-EXPRESSION
```

`@` introduces an invocation. The arguments in `( … )` are evaluated at compile
time and bound to the leading parameters. The **single expression that follows**
is captured as **raw source text** (its verbatim characters) and bound to the
last parameter as a string. The macro typically re-parses that text into an
`Ast` with `parseItem`.

> **Why raw text?** Capturing the trailing source verbatim (rather than parsing
> it inline as the language) lets macro expansion run as an ordinary
> **post-parse pass**. There is no parse-time evaluation and no "install readers
> first" two-pass dance — a macro may be defined anywhere in a file relative to
> its uses.

### Where does `source` end?

`source` is the raw text of **exactly one expression** following `@NAME(…)`. The
parser parses that expression only to find its extent, then hands the macro its
verbatim characters. In `@times(3) log('tick')`, `source` is `log('tick')`.

## Quasiquote and unquote

Building `Ast` by hand is tedious, so two forms construct it from concrete
syntax:

| Form | Meaning |
|------|---------|
| `` `( EXPR ) `` | **quasiquote** — an `Ast` value representing `EXPR` |
| `~name` / `~( EXPR )` | **unquote** — splice an `Ast`-valued result into the surrounding quasiquote |

```
`(sequence(~ast ~(times(n - 1 source))))
```

builds the AST of a call `sequence(<ast> <rest>)` where `<ast>` and `<rest>` are
the `Ast` values produced by the unquoted sub-expressions.

The parentheses after `` ` `` and after `~` are **delimiters**, not tuple syntax.
`` `(()) `` is the quasiquote of the unit expression `()`.

## Using a macro from another file

A `public macro` is exported and may be imported by name, like any other member:

```
// macros.sl
use Compiler:(parseItem)
public macro times = (n source) …

// main.sl
use ./macros:(times)
main = @times(3) log(0)
```

Macro names are **module-scoped**, so two files may reuse a name. There are two
ways to bring one in, mirroring ordinary imports:

- **By name** — `use ./macros:(times)` makes it available unqualified, `@times(…)`.
- **Whole module** — `use ./macros` makes it available qualified by the module's
  namespace, `@macros.times(…)`.

Two files defining `times` only conflict if a single file imports both *by name*
(an unqualified clash); reach them as `@a.times` / `@b.times` instead. Defining
the same name twice *within one file* is a `duplicate_macro` error.

Macros are a whole-program compile-time layer: every module's macros are
collected, type-checked together (so a macro may call one imported from another
file), and used to expand each module. Because a macro has no runtime value,
importing one adds **no** JavaScript import (the name is stripped from the
`use`); the defining module is still compiled for its other exports.

## Macros in (nested) modules

A `macro` may be defined inside a `module`, and its name is **qualified by the
module path** that encloses it:

```
module Macros = (
  public macro times = (n source) …
)

main = @Macros.times(2) log(0)
```

- From **outside** the module, reach it by its qualified name `@Macros.times`
  (nested modules chain, `@Outer.Inner.name`). A bare `@times` does **not** see
  into a module — it is an `unknown_macro` error.
- From **inside** the same module, a macro refers to its siblings (and itself,
  for recursion) by **bare name** — `times(n - 1 source)` above, and `a(source)`
  from a sibling `b` in the same module. Inner scopes shadow outer bare names.
- `public`/private controls only cross-*file* export, exactly as for values.
  Module-nested macros are **not** yet exported across files (only top-level
  `public macro`s are); within a file the qualified name reaches them
  regardless.

Names are resolved per module scope, so the same macro name may be reused in
sibling modules (`@A.inc` / `@B.inc`). Defining the same qualified name twice is
a `duplicate_macro` error.

## The `Compiler` builtin module

```
use Compiler:(Ast parseItem)
```

`Compiler` is a **builtin** module (not a file). It provides:

- **`parseItem : (string): Ast`** — parses one program item (a definition,
  declaration, or bare expression) from a string into an `Ast`. **You must import
  it to use it**: a macro body that calls `parseItem` in a module that does not
  `use Compiler:(parseItem)` is rejected.
- **`Ast`** — an opaque type; the type of quasiquotes and of `parseItem`'s
  result. Importing `Ast` is **optional** — a macro's `-> Ast` return type is
  inferred, so the name `Ast` need not appear in your source. Import it only if
  you write the name explicitly.

So the minimal import is `use Compiler:(parseItem)` when you parse, and a
quasiquote-only macro needs no `Compiler` import at all.

These members are available **only inside macro bodies** (compile-time code). The
`Compiler` import, like every `macro` definition, is **erased** after expansion
and never reaches the type checker or the code generator at the value level.

---

## Type checking

A macro body **is** type-checked — it is an ordinary function `(…) -> Ast`, and
the parameter types are inferred with no annotations. In the example:

- `n` is matched against `0` and used in `n - 1` ⇒ `n : number`
- `source` is passed to `parseItem` ⇒ `source : string`
- the body produces `Ast`, so `times : (number, string): Ast`

So a type error in the *meta-code* is caught at the macro's **definition**:

```
macro bad = (a)
  if (a > 1) { 1 } else { false }   # ERROR: branches differ (number vs boolean)
```

There are therefore **two distinct moments** where HM runs, and nothing escapes:

| Where the ill-typed code is written | When it is rejected |
|---|---|
| In the macro **body** (meta-code) | at the macro's **definition** |
| Inside a `` `( … ) `` **quote** (generated code) | at each **use site**, after expansion |

The code inside a quasiquote is a **template** — data of type `Ast`, not runtime
code. It is *not* type-checked when the macro is defined (it may mention names,
like `sequence` or `log`, that only exist in the target program). It is checked
after expansion, when spliced into the program, by the normal type-checking pass.
So even `` `(if (a > 1) { 1 } else { false }) `` is caught — at the macro's use
site rather than its definition.

`~e` requires `e : Ast` (you can only splice an `Ast` into an `Ast`), and a
quasiquote always has type `Ast` regardless of its contents.

---

## Where it sits in the pipeline

```
parse → macro-expand → module-expand → analyse (HM) → generate
         ^^^^^^^^^^^
         collect `macro` definitions; type-check each body as `(…) -> Ast`;
         expand every `@name(…)` invocation by interpreting the macro
         (binding args + raw source), splice the resulting Ast, repeat to a
         fixpoint; then erase the macro definitions and the `Compiler` import.
```

Because the expanded program is plain AST, the analyser and generator never see
a macro node — they work exactly as before. Source spans (carried on every node)
let a type error inside expanded code point back at the original source.

---

## Rules and constraints

- A macro body must evaluate to an `Ast`.
- Macro parameters are untyped in source but inferred; a body that is not
  well-typed as `(…) -> Ast` is rejected at definition.
- `source` is one following expression's raw text; the macro re-parses it.
- Quasiquote templates are checked post-expansion, at the use site.
- `macro`, like `use`/`public`/`external`/`module`, is a soft keyword.
- `@`, `` ` `` and `~` are otherwise unused, so the syntax never clashes.
- Recursion/mutual reference between macros is allowed (they are compile-time
  functions); expansion iterates to a fixpoint.

---

## Implementation status

The feature is implemented end-to-end:

- **Syntax** — `source/parser/macro_syntax.pl` (+ `grammar`) parses `macro`
  definitions, `@name(…) source` invocations, and `` `( … ) `` / `~…` into
  `macro_definition_node` / `macro_call_node` / `quote_node` / `unquote_node`
  with spans.
- **Type checking** — `analyser/infer.pl` has the `quote_node : Ast` and
  `~e` requires-`Ast` rules; `transformation/macro.pl` `check_macros/1` desugars
  each macro to `(…) -> Ast` and runs Hindley-Milner with `Ast`/`parseItem`
  seeded.
- **Expansion** — `transformation/macro.pl` `expand_macros/2` interprets macro
  bodies (`Ast` values are parser node terms; `parseItem` calls the parser;
  quasiquote rebuilds, splicing unquotes) and replaces each invocation,
  to a fixpoint, then erases macro definitions and the `Compiler` import.
- **Pipeline** — `check_macros` then `expand_macros` run after parse and before
  module expansion (`module_loader.pl`, `compiler.pl`).

### v1 limitations

- **Module-nested macros aren't exported across files:** a `macro` defined
  inside a `module` is reachable within its file by its qualified name
  (`@Math.times`, see [Macros in modules](#macros-in-nested-modules)), but only
  **top-level** `public macro`s can be imported by another file. Exporting a
  module-nested macro across files is not yet supported.
- **`source` is one following expression**, captured as raw text.
- **Spans in generated code** point into the parsed `source` string / the macro
  definition, not the invocation site (good enough for errors; refinable).
- **Nested quasiquote** splicing is single-level; **partial application** inside
  a macro body requires exact arity; a **non-terminating** macro loops (like any
  recursion).
