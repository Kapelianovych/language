# LSP front-end — remaining work

The editor-grade front-end in `source/syntax/` is complete and working: lossless
lexer → recovering parser → green tree → `lower` to the historical AST →
demand-driven incremental analysis (single full-coverage checker = the batch
analyser, cross-file import seeding, reader-macro expansion over the dependency
closure) → JSON-RPC LSP server (diagnostics + hover). The batch compiler is
untouched and its emitted JS is byte-identical to the committed baselines.

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

## 2. LSP feature breadth (today: diagnostics + hover only)

### 2.1 Precise node-at-offset query (prerequisite — highest leverage)
- A query that, given `(File, Offset)`, returns the smallest green-tree node (and
  its lowered AST node / span) covering that offset.
- Unlocks exact hover, go-to-definition, find-references, selection ranges, and
  document highlight in one piece of infrastructure.
- The green tree already has the spans; this is a focused descent over it.

### 2.2 Hover precision
- **Now:** picks the definition whose name is on the cursor's line.
- **Goal:** use the node-at-offset query (2.1) to report the type of the exact
  expression/identifier under the cursor.

### 2.3 Go-to-definition / find-references
- Resolve an identifier at the cursor to its binder (local, top-level, imported,
  constructor) and, in reverse, enumerate uses. Cross-file uses the existing
  interface/import machinery.

### 2.4 Completion, document symbols, signature help, semantic tokens, rename
- None implemented. Document symbols and semantic tokens are the cheapest (a walk
  of the green tree); completion and rename depend on 2.1 + 2.3.

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
- **Macro error spans.** Macro errors surface at `span(0,0)` (file start) instead
  of the offending `@invocation`'s span.
- **Import error messages.** A name absent from a dependency's interface degrades
  to a generic `unbound_variable` rather than a tailored "not exported by <module>".

## Suggested order
1. **2.1 node-at-offset** — unlocks 2.2/2.3 and most of 2.4.
2. **2.2 precise hover** + **2.3 go-to-definition / find-references**.
3. **3.1 UTF-16** and **4 (spans/messages)** — small, improve real-editor fidelity.
4. **2.4 document symbols / semantic tokens**, then completion/rename.
5. **1.1 per-definition granularity** — the largest analyser change; do last,
   measure first (file-granularity may be fast enough in practice).
6. **3.2 incremental sync** — only if reparse-per-keystroke proves too slow.
