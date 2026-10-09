#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# ProjectStore só tem `root` como propriedade de instância; nada de cache/var/memoização.
applies '(^|/)Sources/VibeDeckCore/ProjectStore\.swift'
python3 -I - <<'PY'
import re, sys
f = "Sources/VibeDeckCore/ProjectStore.swift"
lines = open(f).read().split("\n")
start = next((i for i, l in enumerate(lines) if re.match(r'^public struct ProjectStore\b', l)), None)
if start is None:
    print(f"{f}: 'public struct ProjectStore' não encontrado (virou class/actor?)"); sys.exit(1)
bad = 0
prop = re.compile(r'^    (?:(?:public|private|fileprivate|internal|nonisolated(?:\(unsafe\))?)\s+)*(static\s+)?(let|var)\s+(\w+)(.*)$')
for i in range(start + 1, len(lines)):
    l = lines[i]
    if l == "}": break
    m = prop.match(l)
    if not m: continue
    static, kind, name, rest = m.groups()
    computed = "=" not in rest and "{" in rest
    if computed: continue
    if static:
        if kind == "var":
            print(f"{f}:{i+1}: 'static var {name}' é estado global mutável no ProjectStore"); bad += 1
        continue
    if name != "root":
        print(f"{f}:{i+1}: propriedade armazenada '{name}' — ProjectStore só pode guardar `root`"); bad += 1
    elif kind != "let":
        print(f"{f}:{i+1}: `root` deve ser let"); bad += 1
if any(re.search(r'\bmutating func\b', l) for l in lines[start:]):
    print(f"{f}: 'mutating func' dentro do ProjectStore"); bad += 1
sys.exit(1 if bad else 0)
PY
