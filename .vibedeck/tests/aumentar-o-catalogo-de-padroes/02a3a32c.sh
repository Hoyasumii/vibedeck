#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
py <<'PY' || fail=1
import _catalog as c
want = {
 "bdd": ("Desenvolvimento orientado a comportamento", "practices"), "design-by-contract": ("Design por contrato", "practices"),
 "modular-monolith": ("Monólito modular", "architecture"), "event-driven": ("Arquitetura orientada a eventos", "architecture"),
 "value-object": ("Objeto de valor", "domain"), "domain-service": ("Serviço de domínio", "domain"),
 "composite": ("Composição", "design"), "proxy": ("Representante", "design")}
cat = {t["id"]: t for t in c.load()}; head = {t["id"] for t in c.original_catalog()}; bad = []
for i, (name, cat_) in want.items():
    t = cat.get(i)
    if not t: bad.append(f"{i}: ausente"); continue
    if t["name"] != name: bad.append(f"{i}: name {t['name']!r} != {name!r}")
    if t["category"] != cat_: bad.append(f"{i}: category {t['category']!r} != {cat_!r}")
added = set(cat) - head
if added != set(want): bad.append(f"lote difere do escopo: extras={sorted(added - set(want))} faltando={sorted(set(want) - added)}")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
