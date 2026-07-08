# Tests

A tiny, dependency-free test harness (Scryer 0.10 ships no plunit). Run from the
**repository root** — fixture directories are resolved relative to the working
directory:

```sh
scryer-prolog test/run.pl              # run every suite; exits non-zero on failure
scryer-prolog test/run.pl -- --bless   # regenerate golden expectations
```

## Suites

### Golden (`golden.pl`)

Whole-pipeline snapshot tests. For every `test/fixtures/golden/NAME.sl` the suite runs
`compiler:compile/3` (source text → JS text — no filesystem, no module resolver)
and asserts the output equals `test/fixtures/golden/NAME.js.expected`.

Because `compile/3` has no module resolver, golden fixtures must be
**self-contained, import-free** programs (no `use`).

On a mismatch the actual output is written to `NAME.js.actual` next to the
expected file (gitignored) so you can `diff` the two. When the compiler's output
changes on purpose, review the diff, then regenerate every expectation with
`--bless` and commit the updated `.js.expected` files.

### Round-trip (`roundtrip.pl`)

Lossless-property tests over every `*.sl` in both `test/fixtures/golden` and
`test/fixtures/roundtrip`:

- **lexer** — `tokens_text(tokenize(S)) == S`
- **parser** — `green_text(parse_tokens(tokenize(S))) == S`

These must hold for *any* input, so `test/fixtures/roundtrip/` holds the tricky cases
that need not compile: comments, trailing whitespace, Unicode identifiers, and
malformed programs the recovering parser must still reproduce verbatim.

## Adding fixtures

- **A code-generation case:** drop `NAME.sl` in `test/fixtures/golden/`, run `--bless`,
  eyeball the generated `NAME.js.expected`, commit both. It is automatically
  round-tripped too.
- **A lossless-only case** (invalid or awkward source): drop `NAME.sl` in
  `test/fixtures/roundtrip/`. Nothing to bless.

## Layout

| File              | Role                                                  |
|-------------------|-------------------------------------------------------|
| `run.pl`          | entry point; runs suites or `--bless`, sets exit code |
| `test_harness.pl` | reporting + char-list file I/O + fixture enumeration  |
| `golden.pl`       | golden/snapshot suite and `--bless`                   |
| `roundtrip.pl`    | lexer/parser round-trip suite                         |
