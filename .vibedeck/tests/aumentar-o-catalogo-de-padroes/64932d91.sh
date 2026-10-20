#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$TESTS" 'addPatterns\(PatternCatalog\.all\.map\(\\?\.id\)|addPatterns\(' "nenhum teste chama addPatterns"
body "$TESTS" '@Test func everyCatalogTemplateCreatesItsEnforcedTopic' > /tmp/vd_body_$$ || true
b=$(cat /tmp/vd_body_$$); rm -f /tmp/vd_body_$$
for pat in 'PatternCatalog\.all' 'sourcePattern == template\.id' 'rules\.count == template\.rules\.count'; do
  printf '%s' "$b" | grep -E "$pat" >/dev/null || { echo "$TESTS: everyCatalogTemplateCreatesItsEnforcedTopic não confere '$pat'"; fail=1; }
done
run_tests PatternsTests/everyCatalogTemplateCreatesItsEnforcedTopic
finish
