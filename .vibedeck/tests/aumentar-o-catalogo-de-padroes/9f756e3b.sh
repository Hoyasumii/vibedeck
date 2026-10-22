#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
body "$TESTS" '    fn regras_novas_trazem_verificacao_concreta' > /tmp/vd_b_$$; b=$(cat /tmp/vd_b_$$); rm -f /tmp/vd_b_$$
for pat in 'NEW_CATEGORIES' 'starts_with\("Verificar:"\)' 'rule\.details'; do
  printf '%s' "$b" | grep -E "$pat" >/dev/null || { echo "$TESTS: regras_novas_trazem_verificacao_concreta não confere '$pat'"; fail=1; }
done
py <<'PY' || fail=1
import re, os
t = open(os.environ["TESTS"]).read()
m = re.search(r"const NEW_CATEGORIES: \[\(&str, &str\); \d+\] = \[(.*?)\n    \];", t, re.S)
ids = set(re.findall(r'\("([a-z-]+)",', m.group(1)))
want = set(os.environ["NEW_IDS"].split())
if ids != want: print(f"NEW_CATEGORIES difere dos oito novos: {sorted(ids ^ want)}"); raise SystemExit(1)
PY
run_tests $TESTS regras_novas_trazem_verificacao_concreta
finish
