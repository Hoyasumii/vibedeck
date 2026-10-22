#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
body "$TESTS" '    fn toda_referencia_resolve_sem_ambiguidade' > /tmp/vd_b_$$; b=$(cat /tmp/vd_b_$$); rm -f /tmp/vd_b_$$
for pat in 'chain\(std::iter::once\(&t\.name\)\)' 'chain\(t\.aliases\.iter\(\)\)' 'x\.matches_exactly\(r\)' 'assert_eq!\(matches, \[t\.id\.as_str\(\)\]' 'PatternCatalog::find\(r\)\.unwrap\(\)\.id, t\.id'; do
  printf '%s' "$b" | grep -E "$pat" >/dev/null || { echo "$TESTS: toda_referencia_resolve_sem_ambiguidade não confere '$pat'"; fail=1; }
done
run_tests $TESTS toda_referencia_resolve_sem_ambiguidade
finish
