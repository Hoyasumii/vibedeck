#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
body "$TESTS" '@Test func everyCatalogReferenceResolvesUnambiguously' > /tmp/vd_b_$$; b=$(cat /tmp/vd_b_$$); rm -f /tmp/vd_b_$$
for pat in 'template\.id, template\.name\] \+ template\.aliases' 'matches\(exactly: reference\)' 'PatternCatalog\.find\(reference\)\?\.id == template\.id' 'matches\.map\(\\\.id\) == \[template\.id\]'; do
  printf '%s' "$b" | grep -qE "$pat" || { echo "$TESTS: everyCatalogReferenceResolvesUnambiguously não confere '$pat'"; fail=1; }
done
run_tests PatternsTests/everyCatalogReferenceResolvesUnambiguously
finish
