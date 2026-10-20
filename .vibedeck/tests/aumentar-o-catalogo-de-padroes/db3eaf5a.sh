#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$VIEW" 'PatternCatalog\.all' "lista não deriva de PatternCatalog.all"
need "$VIEW" 'PatternCategory\.all' "lista não deriva de PatternCategory.all"
# sem ids de padrões fixos na view; toda categoria usada por um template tem case em label(_:)
py <<'PY' || fail=1
import _catalog as c, os, re, sys
bad = []
view = open(os.environ["VIEW"], encoding="utf-8").read()
for n, line in enumerate(view.splitlines(), 1):
    for t in c.load():
        if f'"{t["id"]}"' in line: bad.append(f'{os.environ["VIEW"]}:{n}: id fixo de padrão {t["id"]!r}')
lab = re.search(r"static func label\(.*?\n    \}", open(os.environ["PAT"], encoding="utf-8").read(), re.S).group(0)
cats = re.findall(r'"(\w+)"', re.search(r"PatternCategory \{\s*public static let all = \[(.*?)\]", open(os.environ["PAT"]).read(), re.S).group(1))
for k in {t["category"] for t in c.load()}:
    if k not in cats: bad.append(f"categoria {k!r} fora de PatternCategory.all")
    if f'case "{k}"' not in lab: bad.append(f"categoria {k!r} sem case em label(_:)")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
