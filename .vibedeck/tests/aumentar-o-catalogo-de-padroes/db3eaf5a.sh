#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$VIEW" 'PatternCatalog\.all' "lista não deriva de PatternCatalog.all"
need "$VIEW" 'PatternCategory\.all' "lista não deriva de PatternCategory.all"
# sem ids de padrões fixos na view; toda categoria usada por um template tem case em label (Core Rust e app)
py <<'PY' || fail=1
import _catalog as c, os, re, sys
bad = []
view = open(os.environ["VIEW"], encoding="utf-8").read()
for n, line in enumerate(view.splitlines(), 1):
    for t in c.load():
        if f'"{t["id"]}"' in line: bad.append(f'{os.environ["VIEW"]}:{n}: id fixo de padrão {t["id"]!r}')

lab_rs = re.search(r"pub fn label\(.*?\n    \}", open(os.environ["PAT"], encoding="utf-8").read(), re.S).group(0)
lab_sw = re.search(r"static func label\(.*?\n    \}", open(os.environ["APPPAT"], encoding="utf-8").read(), re.S).group(0)
cats_rs = re.findall(r'"(\w+)"', re.search(r"pub const ALL: \[&'static str; \d+\] = \[(.*?)\]", open(os.environ["PAT"]).read(), re.S).group(1))

cats_sw = re.findall(r'"(\w+)"', re.search(r"enum PatternCategory \{\s*static let all = \[(.*?)\]", open(os.environ["APPPAT"]).read(), re.S).group(1))
for k in {t["category"] for t in c.load()}:
    if k not in cats_rs: bad.append(f"categoria {k!r} fora de PatternCategory::ALL")
    if k not in cats_sw: bad.append(f"categoria {k!r} fora de PatternCategory.all do app")
    if f'Some("{k}")' not in lab_rs: bad.append(f"categoria {k!r} sem case em label do Core")
    if f'case "{k}"' not in lab_sw: bad.append(f"categoria {k!r} sem case em label(_:) do app")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
finish
