#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Slug.make mantém suas regras; criação de doc/grupo/tópico/ideia usa uniqueSlug(Slug.make(...)); sem slug à mão.
applies '(^|/)Sources/VibeDeckCore/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
store = open("Sources/VibeDeckCore/ProjectStore.swift").read()
m = re.search(r'public enum Slug \{.*?\n\}', store, re.S)
s = m.group(0) if m else ""
for needle, why in [(".diacriticInsensitive", "remover acentos"), ("scalar.isASCII", "só ASCII"), ("CharacterSet.alphanumerics", "alfanumérico"),
                    ("caseInsensitive", "minúsculas"), ('out.append("-")', "separador -"), ("prefix(60)", "corte em 60"), ('"untitled"', "fallback untitled")]:
    if needle not in s:
        print(f"Sources/VibeDeckCore/ProjectStore.swift: Slug.make perdeu '{why}' ({needle})"); bad += 1
u = re.search(r'func uniqueSlug\(.*?\n    \}', store, re.S)
if not u or '"\\(base)-\\(n)"' not in u.group(0) or "n = 2" not in u.group(0):
    print("Sources/VibeDeckCore/ProjectStore.swift: uniqueSlug deve acrescentar -2, -3... se o arquivo existir"); bad += 1
for d in ["docsDir", "reviewsDir", "rulesDir", "ideasDir"]:
    if not re.search(r'uniqueSlug\(Slug\.make\(\w+\), in: %s,' % d, store):
        print(f"Sources/VibeDeckCore/ProjectStore.swift: criação em {d} deve usar uniqueSlug(Slug.make(título), in: {d}, ...)"); bad += 1
hand = re.compile(r'replacingOccurrences\(of: " ", with: "-"\)|components\(separatedBy: " "\)\.joined\(separator: "-"\)')
for f in sorted(glob.glob("Sources/VibeDeckCore/*.swift")):
    for n, l in enumerate(open(f).read().split("\n"), 1):
        if hand.search(l) and not l.strip().startswith("//"):
            print(f"{f}:{n}: slug montado à mão; use Slug.make: {l.strip()}"); bad += 1
sys.exit(1 if bad else 0)
PY
