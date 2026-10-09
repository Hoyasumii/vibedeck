#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Erros de usuário via VibeDeckError (pt-BR): sem fatalError/NSError/throw de string solta no Core.
applies '(^|/)Sources/VibeDeckCore/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
pat = re.compile(r'\bfatalError\(|\bNSError\(|\bthrow\s+"|\bthrow\s+NSError|\bpreconditionFailure\(')
for f in sorted(glob.glob("Sources/VibeDeckCore/*.swift")):
    for n, l in enumerate(open(f).read().split("\n"), 1):
        if pat.search(l) and not l.strip().startswith("//"):
            print(f"{f}:{n}: use um case de VibeDeckError com errorDescription em português: {l.strip()}"); bad += 1
# Descrições dos cases de VibeDeckError: nenhuma parece inglês.
src = open("Sources/VibeDeckCore/ProjectStore.swift").read()
m = re.search(r'var errorDescription: String\? \{.*?\n    \}', src, re.S)
EN = set("the and to of is are for with from or an in on not this that be it as at by will can has have if when your you could found".split())
for l in (m.group(0) if m else "").split("\n"):
    for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', l):
        words = set(re.findall(r"[a-z]+", re.sub(r'\\\([^)]*\)', ' ', lit).lower()))
        if len(words & EN) >= 2:
            print(f"Sources/VibeDeckCore/ProjectStore.swift: errorDescription parece inglês: {lit}"); bad += 1
cases = set(re.findall(r'^    case (\w+)', src.split("public var errorDescription")[0], re.M))
described = set(re.findall(r'case \.(\w+)', m.group(0))) if m else set()
for c in sorted(cases - described):
    print(f"Sources/VibeDeckCore/ProjectStore.swift: VibeDeckError.{c} sem errorDescription"); bad += 1
sys.exit(1 if bad else 0)
PY
