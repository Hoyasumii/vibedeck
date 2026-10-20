#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
py <<'PY' || fail=1
import _catalog as c, os, re
cat = {t["id"]: t for t in c.load()}; bad = []
vague = re.compile(r"\b(bom|boa|bons|boas|adequad[oa]s?|quando poss[ií]vel|se poss[ií]vel|conforme necess[aá]rio|razo[aá]vel|razo[aá]veis)\b", re.I)
for i in os.environ["NEW_IDS"].split():
    for n, r in enumerate(cat[i]["rules"], 1):
        w = f"{i} regra {n}"
        if not r["text"].strip(): bad.append(f"{w}: texto vazio")
        d = r["details"] or ""
        if not d.startswith("Verificar:"): bad.append(f"{w}: details não começa com Verificar:")
        elif not d[len("Verificar:"):].strip(): bad.append(f"{w}: Verificar: vazio")
        for s, v in (("texto", r["text"]), ("details", d)):
            m = vague.search(v)
            if m: bad.append(f"{w}: termo vago {m.group(0)!r} em {s}")
        if "\n" in r["text"]: bad.append(f"{w}: texto com mais de uma linha")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
