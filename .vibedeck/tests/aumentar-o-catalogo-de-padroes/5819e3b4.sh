#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
py <<'PY' || fail=1
import _catalog as c, os, re
bad = []
pat = re.compile(r"(\.swift\b|\.xcodeproj|Package\.swift|Sources/|Tests/|\.vibedeck|vibedeck\.json|VibeDeck\w*|\bProjectStore\b|\bPatternCatalog\b|\bPatternTemplate\b|\bRuleSeverity\b|\bClaudeSession\b|\bMCPServer\b|\bSwiftUI\b)", re.I)
for t in c.load():
    fields = [("summary", t["summary"]), ("name", t["name"])] + [("alias", a) for a in t["aliases"]]
    for n, r in enumerate(t["rules"], 1): fields += [(f"regra {n} texto", r["text"]), (f"regra {n} details", r["details"] or "")]
    for k, v in fields:
        m = pat.search(v)
        if m: bad.append(f"{t['id']} {k}: cita {m.group(0)!r}")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
