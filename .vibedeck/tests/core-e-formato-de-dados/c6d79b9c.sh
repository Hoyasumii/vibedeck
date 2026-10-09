#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# encode(to:): opcionais com encodeIfPresent; tags/paths só se não vazios.
applies '(^|/)Sources/VibeDeckCore/'
python3 -I - <<'PY'
import glob, re, sys
bad = 0
decl = re.compile(r'^    (?:(?:public|private|fileprivate|internal)\s+)*(?:let|var)\s+(\w+)\s*:\s*([^={]+?)\s*(?:=.*)?$')
for f in sorted(glob.glob("Sources/VibeDeckCore/*.swift")):
    lines = open(f).read().split("\n")
    i = 0
    while i < len(lines):
        if not re.match(r'^(?:public )?struct \w+', lines[i]): i += 1; continue
        j = i + 1
        while j < len(lines) and lines[j] != "}": j += 1
        block = lines[i:j]
        types = {}
        for l in block:
            m = decl.match(l)
            if m and "{" not in l: types[m.group(1)] = m.group(2).strip()
        k = next((x for x, l in enumerate(block) if "func encode(to" in l), None)
        if k is not None:
            for x in range(k + 1, len(block)):
                if block[x] == "    }": break
                m = re.match(r'^\s*try\s+\w+\.encode\((\w+),\s*forKey:', block[x])
                if not m: continue
                name = m.group(1)
                t = types.get(name, "")
                if t.endswith("?"):
                    print(f"{f}:{i+x+1}: '{name}' é opcional; use encodeIfPresent"); bad += 1
                elif name in ("tags", "paths"):
                    print(f"{f}:{i+x+1}: '{name}' vazio deve ser omitido: if !{name}.isEmpty {{ ... }}"); bad += 1
        i = j + 1
sys.exit(1 if bad else 0)
PY
