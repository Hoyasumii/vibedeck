#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Toda escrita no Core passa por AtomicFile.write (a única que chama Data.write direto).
applies '(^|/)Sources/VibeDeckCore/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
pat = re.compile(r'\.write\(to:|\.write\(toFile:|\bcreateFile\(|\.write\(contentsOfFile')
for f in sorted(glob.glob("Sources/VibeDeckCore/*.swift")):
    inside = False
    for n, l in enumerate(open(f).read().split("\n"), 1):
        if re.match(r'^public enum AtomicFile\b', l): inside = True
        elif inside and l == "}": inside = False
        if inside or l.strip().startswith("//"): continue
        if pat.search(l):
            print(f"{f}:{n}: escrita direta fora de AtomicFile.write: {l.strip()}"); bad += 1
src = open("Sources/VibeDeckCore/ProjectStore.swift").read()
m = re.search(r'public enum AtomicFile \{.*?\n\}', src, re.S)
if not m or "createDirectory" not in m.group(0) or "options: .atomic" not in m.group(0):
    print("Sources/VibeDeckCore/ProjectStore.swift: AtomicFile.write deve criar o diretório pai e gravar com .atomic"); bad += 1
sys.exit(1 if bad else 0)
PY
