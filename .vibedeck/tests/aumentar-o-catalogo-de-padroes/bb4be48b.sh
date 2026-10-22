#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
run_tests $TESTS catalogo_expandido_tem_os_templates_esperados
py <<'PY' || fail=1
import _catalog as c, os, re
cats = re.search(r"pub const ALL: \[&'static str; \d+\] = \[(.*?)\]", open(os.environ["PAT"]).read(), re.S).group(1)
cats = re.findall(r'"(\w+)"', cats)
ids = [t["id"] for t in c.load()]
bad = [f"{i}: id duplicado" for i in set(ids) if ids.count(i) > 1]
for t in c.load():
    if t["category"] not in cats: bad.append(f"{t['id']}: category {t['category']!r} fora de PatternCategory::ALL")
    if not t["name"].strip(): bad.append(f"{t['id']}: name vazio")
    if not t["summary"].strip(): bad.append(f"{t['id']}: summary vazio")
    if not t["rules"]: bad.append(f"{t['id']}: sem regras")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
