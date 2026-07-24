# LSP front-end — remaining work

The editor-grade front-end is complete and working: lossless lexer → recovering
parser → green tree → `lower` to the historical AST (all in `source/syntax/`,
shared with the batch compiler) → demand-driven incremental analysis (single
full-coverage checker = the batch analyser, cross-file import seeding,
reader-macro expansion over the dependency closure) → JSON-RPC LSP server
(diagnostics + hover + semantic tokens) (the incremental engine and JSON-RPC
loop live in `lsp/`). The batch compiler is untouched and its emitted JS is
byte-identical to the committed baselines.

This document tracks what is left. Nothing here is a bug; it is depth and breadth.

## 1. Correctness / granularity

### 1.1 Per-definition type granularity
- **Now:** type-checking is incremental at *file* granularity (the analyser is
  whole-program). Editing one definition re-checks the whole file.
- **Goal:** firewall type-checking per top-level definition so an edit only
  re-checks the definitions that (transitively) depend on it. Parsing is already
  finer (green tree); the type firewall stops at the file boundary.
- **Notes:** the analyser would need a per-definition entry point with explicit
  dependency tracking between definitions, or the engine would need to slice the
  AST per definition and seed each from the others' inferred types. Validate
  against the byte-identical baselines.

### 1.2 Macro expansion is per-closure
- **Now:** editing any file in a macro user's dependency closure re-expands it.
- **Assessment:** this is the *correct* granularity for a whole-program layer and
  is probably fine to leave. Listed only for completeness.

## 2. LSP feature breadth (today: diagnostics + hover)

### 2.1 Precise node-at-offset query (prerequisite — highest leverage) — DONE
- `queries:node_at(File, Offset)` returns `found(EnclosingKind, span(NS,NE),
  Token)` — the smallest green node covering the offset and the leaf the cursor
  sits on (`token(Kind, Text, span(TS,TE))` or `none`), or `none` when the
  offset is outside the tree. A focused descent over the green tree's spans.
- Still unlocks go-to-definition, find-references, selection ranges, and
  document highlight — each is "call `node_at`, then interpret the result".

### 2.2 Hover precision — PARTLY DONE
- **Was:** picked the definition whose name is on the cursor's line.
- **Now:** `node_at` gives the identifier token under the cursor, so hover
  resolves at a USE site too (not only the definition line); if that name is a
  top-level definition, its type is shown. Line heuristic kept as a fallback.
- **Remaining:** per-expression types (the analyser exposes only top-level
  definition types), so hover over an arbitrary sub-expression is not yet exact.

### 2.3 Go-to-definition / find-references
- Resolve an identifier at the cursor to its binder (local, top-level, imported,
  constructor) and, in reverse, enumerate uses. Cross-file uses the existing
  interface/import machinery.

### 2.4 Completion, document symbols, signature help, semantic tokens, rename
- **Semantic tokens** — DONE (2026-07-24). `source/syntax/semantic_tokens.pl`
  walks the raw green tree (not the lowered AST — trivia/keywords/operators
  need colouring too) and emits `tok(Type, Start, End)` for every leaf;
  `queries:semantic_tokens(File)` memoises it off `parse` (so it firewalls
  exactly like `program_ast`); `lsp.pl` advertises the legend + `full: true`
  in `initialize`, serves `textDocument/semanticTokens/full`, and delta-
  encodes per the LSP wire format in one pass (no re-scan per token). 15
  token types (namespace/type/typeParameter/parameter/variable/property/
  enumMember/function/method/macro/keyword/comment/string/number/operator),
  no modifiers. Most of the tree needs no special case at all — type-shaped
  green nodes (`type_name`, `type_param`, `variant`, ...) are self-describing
  regardless of nesting, and a bare identifier defaults to `variable`; only
  ~15 PARENT kinds whose child's role isn't otherwise visible in the tree
  shape (a function's parameter list vs. a tuple literal's member list, both
  `member` nodes; `type_declaration`'s bare name leaf vs. `macro_definition`'s)
  get an explicit `special/4` override. Verified against the full standard
  library (850 tokens) and every fixture (`golden/`, `roundtrip/`, including
  the malformed/error-recovery one) — no crash, strictly ascending `Start`
  everywhere — plus a real framed JSON-RPC session end to end. Known
  imprecisions: soft keywords used as an ordinary variable READ (not a
  declaration) still colour `keyword` by text; `obj.method(...)` colours
  `method` as `property`; `|` is always `operator` even as an arm/variant
  separator. Document symbols are the next-cheapest green-tree walk;
  completion and rename depend on 2.1 + 2.3.

## 3. Protocol fidelity

### 3.1 UTF-16 positions
- **Now:** offset↔{line,character} conversion counts characters — correct only for
  the BMP.
- **Goal:** index `character` as a UTF-16 code unit (astral-plane characters count
  as two), at the LSP boundary only; engine offsets stay char-based.

### 3.2 Incremental document sync
- **Now:** full-document sync (`textDocumentSync: 1`); the engine reparses the
  whole buffer per keystroke (cheap, but not minimal).
- **Goal:** apply incremental `didChange` ranges and feed the engine a minimal
  edit, so re-lexing/re-parsing can reuse unchanged green-tree spans.

## 4. Smaller follow-ups
- **Macro error spans.** — DONE. A macro-invocation error is wrapped
  `analysis_error(at(Span, Reason))` at the `@invocation` (unknown macro in
  `resolve_uses`, and interpretation-time errors via the `expand_term` catch,
  keeping the innermost span for nested macros); `queries` splits that back into
  `error_at(Span, Reason)`. Whole-program macro errors (e.g. a duplicate macro)
  still have no invocation site and report at file start.
- **Import error messages.** — DONE. A name a dependency does not export is now
  reported as `error_at(useSpan, name_not_exported(Path, Name))` (rendered
  "`Name` is not exported by `Path`"), threaded out of `import_seeds` and folded
  into the file's diagnostics. The name is still left unseeded, so it may also
  surface as an `unbound_variable` at its use sites; suppressing that secondary
  error would need a placeholder seed and is left as a follow-up.

## Suggested order
1. ~~**2.1 node-at-offset**~~ — DONE. ~~**4 (spans/messages)**~~ — DONE.
   ~~**2.4 semantic tokens**~~ — DONE.
2. **2.3 go-to-definition / find-references** — next; builds on `node_at` (the
   identifier token under the cursor) plus the existing interface/import machinery.
3. **3.1 UTF-16 positions** — small, improves real-editor fidelity.
4. **2.4 document symbols** (cheap green-tree walk, same shape as semantic
   tokens), then completion/rename (need 2.3).
5. **2.2 exact sub-expression hover** — needs per-node types (see 1.1).
6. **1.1 per-definition granularity** — the largest analyser change; do last,
   measure first (file-granularity may be fast enough in practice).
7. **3.2 incremental sync** — only if reparse-per-keystroke proves too slow.
