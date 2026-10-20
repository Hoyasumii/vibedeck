#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
py <<'PY' || fail=1
import _catalog as c, os
cat = {t["id"]: t for t in c.load()}; bad = []
for i in os.environ["NEW_IDS"].split():
    t = cat.get(i)
    if not t: bad.append(f"{i}: ausente"); continue
    extra = [a for a in t["aliases"] if c.slug(a) not in (c.slug(t["id"]), c.slug(t["name"]))]
    if len(extra) < 1: bad.append(f"{i}: sem aliases além de id/nome")
    if c.slug(t["id"]) == c.slug(t["name"]) and not extra: bad.append(f"{i}: sem nome em outro idioma")
    # nome em um idioma (pt) e id/aliases em outro (en): precisa de ao menos 2 referências distintas além do id
    distinct = {c.slug(r) for r in c.refs(t)}
    if len(distinct) < 3: bad.append(f"{i}: só {len(distinct)} referências distintas (id, nome e aliases); esperado >= 3 (pt, en e sigla/nome comum)")
    for r in c.refs(t):
        if not c.matches(t, r): bad.append(f"{i}: {r!r} não resolve")
# exemplo da regra
d = [t for t in c.load() if c.matches(t, "domain-driven design")]
if [t["id"] for t in d] != ["ddd"]: bad.append("domain-driven design não resolve para ddd")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
