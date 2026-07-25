#!/bin/sh
# check.sh -- regenerate the parser and parse every real .sl file in the repo,
# reporting which ones produced an ERROR/MISSING node. Dev-only script, not
# part of the grammar package itself.
cd "$(dirname "$0")" || exit 1
pkgx +nodejs.org +tree-sitter.github.io tree-sitter generate || exit 1
FAIL=0
for f in ../test/fixtures/golden/*.sl ../test/fixtures/roundtrip/*.sl ../libraries/Std.sl; do
  # `tree-sitter parse` exits non-zero whenever it emits an ERROR node --
  # exactly the case this script exists to detect, so it must NOT abort the
  # loop (no `set -e`: it silently killed this script on the first real
  # failure once, before printing anything about it).
  OUT=$(pkgx +nodejs.org +tree-sitter.github.io tree-sitter parse "$f" 2>&1)
  if echo "$OUT" | grep -q "ERROR\|MISSING"; then
    echo "FAIL: $f"
    echo "$OUT" | grep "ERROR\|MISSING" | head -5
    FAIL=1
  fi
done
if [ "$FAIL" = "0" ]; then
  echo "ALL OK"
fi
