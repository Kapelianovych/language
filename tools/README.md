# tools

## `generate_unicode.pl`

Regenerates [`source/unicode.pl`](../source/unicode.pl)
from the Unicode character database.

`identifier.pl` recognises an identifier as an `XID_Start` character followed
by zero or more `XID_Continue` characters (Unicode UAX #31). Those two
properties live in the UCD file `DerivedCoreProperties.txt`. This script reads
that file directly — from a local path with `library(pio)`, or straight from
unicode.org with `library(http/http_open)` — merges the codepoint ranges, and
emits a Prolog module that tests membership with an O(log n) balanced binary
search tree (stored as id-keyed `xs_node`/`xc_node` facts so Scryer's
first-argument indexing applies).

### Usage

Scryer passes script arguments after `--`:

```sh
# From a local copy of the UCD file:
scryer-prolog tools/generate_unicode.pl -- --ucd path/to/DerivedCoreProperties.txt

# Or fetch it from unicode.org (latest, or a pinned version):
scryer-prolog tools/generate_unicode.pl -- --download
scryer-prolog tools/generate_unicode.pl -- --download --unicode-version 17.0.0
```

By default the result is written to `source/parser/identifier.pl`; pass
`--output PATH` (or `-o PATH`) to write elsewhere. The generated file records
which Unicode version it came from in its header.
