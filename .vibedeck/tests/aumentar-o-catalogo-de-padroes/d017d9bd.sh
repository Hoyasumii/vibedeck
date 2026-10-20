#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
py <<'PY' || fail=1
import _catalog as c
old = c.head_catalog(); new = {t["id"]: t for t in c.load()}; bad = []
if len(old) != 24: bad.append(f"HEAD tem {len(old)} templates, esperado 24")
for t in old:
    n = new.get(t["id"])
    if not n: bad.append(f"{t['id']}: removido"); continue
    for k in ("name", "category", "summary", "aliases", "rules"):
        if n[k] != t[k]: bad.append(f"{t['id']}: {k} alterado")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
