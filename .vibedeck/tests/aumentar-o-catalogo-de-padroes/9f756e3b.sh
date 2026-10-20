#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
body "$TESTS" '@Test func newRulesHaveConcreteVerificationDetails' > /tmp/vd_b_$$; b=$(cat /tmp/vd_b_$$); rm -f /tmp/vd_b_$$
for pat in 'newCategories\.keys' 'hasPrefix\("Verificar:"\)' 'rule\.details'; do
  printf '%s' "$b" | grep -qE "$pat" || { echo "$TESTS: newRulesHaveConcreteVerificationDetails não confere '$pat'"; fail=1; }
done
py <<'PY' || fail=1
import re, os
t = open(os.environ["TESTS"]).read()
m = re.search(r"newCategories = \[(.*?)\n    \]", t, re.S)
ids = set(re.findall(r'"([a-z-]+)":', m.group(1)))
want = set(os.environ["NEW_IDS"].split())
if ids != want: print(f"newCategories difere dos oito novos: {sorted(ids ^ want)}"); raise SystemExit(1)
PY
run_tests PatternsTests/newRulesHaveConcreteVerificationDetails
finish
