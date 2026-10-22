#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$ITESTS" 'add_patterns\(' "nenhum teste chama add_patterns"
body "$ITESTS" 'fn todo_template_cria_seu_topico' > /tmp/vd_body_$$ || true
b=$(cat /tmp/vd_body_$$); rm -f /tmp/vd_body_$$
for pat in 'PatternCatalog::all\(\)' 'source_pattern\.as_deref\(\), Some\(t\.id\.as_str\(\)\)' 'topic\.rules\.len\(\), t\.rules\.len\(\)'; do
  printf '%s' "$b" | grep -E "$pat" >/dev/null || { echo "$ITESTS: todo_template_cria_seu_topico não confere '$pat'"; fail=1; }
done
run_tests $ITESTS todo_template_cria_seu_topico
finish
