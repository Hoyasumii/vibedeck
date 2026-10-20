#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
py <<'PY' || fail=1
import _catalog as c
cat = c.load(); bad = []
for t in cat:
    if c.slug(t["id"]) != t["id"]: bad.append(f"{t['id']}: id não é slug (Slug.make = {c.slug(t['id'])})")
    for r in c.refs(t):
        others = [o["id"] for o in cat if o is not t and c.matches(o, r)]
        if others: bad.append(f"{t['id']}: referência {r!r} também casa com {others}")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
