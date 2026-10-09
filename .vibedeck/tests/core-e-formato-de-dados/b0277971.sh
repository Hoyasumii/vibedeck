#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Busca por prefixo de UUID só nos helpers (resolveSlug, matchRule, findItem, resolveRunRef), com >= 4 chars.
applies '(^|/)Sources/VibeDeckCore/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
ALLOWED = {"resolveSlug", "matchRule", "findItem", "resolveRunRef"}
for f in sorted(glob.glob("Sources/VibeDeckCore/*.swift")):
    lines = open(f).read().split("\n")
    for n, l in enumerate(lines):
        if l.strip().startswith("//") or not re.search(r'uuidString(\.lowercased\(\))?\.hasPrefix|[iI]d\.hasPrefix\(needle\)', l): continue
        fn = next((re.search(r'func (\w+)', lines[k]).group(1) for k in range(n, -1, -1) if re.search(r'\bfunc \w+', lines[k])), "?")
        if fn not in ALLOWED:
            print(f"{f}:{n+1}: busca por prefixo de id reimplementada em '{fn}'; reutilize resolveSlug/matchRule/findItem"); bad += 1
store = open("Sources/VibeDeckCore/ProjectStore.swift").read()
def body(name):
    m = re.search(r'func %s\b.*?\n    \}' % name, store, re.S)
    return m.group(0) if m else ""
for fn, needles in {
    "resolveSlug": ["$0.slug == ref", "id.uuidString.lowercased() == needle", "caseInsensitiveCompare(ref)", "Slug.make(ref)",
                    "needle.count >= 4", "prefixed.count == 1", "fileExists(atPath: dir.appending(path: \"\\(ref).json\").path) { return ref }"],
    "matchRule": ["needle.count >= 4", "VibeDeckError.ruleNotFound", "VibeDeckError.ambiguousRule"],
    "findItem": ["needle.count >= 4", "VibeDeckError.itemNotFound", "VibeDeckError.ambiguousItem"],
}.items():
    b = body(fn)
    for s in needles:
        if s not in b:
            print(f"Sources/VibeDeckCore/ProjectStore.swift: {fn} perdeu o comportamento '{s}'"); bad += 1
sys.exit(1 if bad else 0)
PY
