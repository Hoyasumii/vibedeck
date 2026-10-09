#!/usr/bin/env bash
# O $id de cada schema/v1/<nome>.schema.json é exatamente SchemaURL.base + "/<nome>.schema.json".
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^schema/|^Sources/VibeDeckCore/Models\.swift$'; then exit 77; fi
python3 -I - <<'PY'
import re, sys, glob, json, os
m = re.search(r'static let base\s*=\s*"([^"]+)"', open("Sources/VibeDeckCore/Models.swift").read())
if not m:
    print("Sources/VibeDeckCore/Models.swift: SchemaURL.base não encontrado"); sys.exit(1)
base = m.group(1).rstrip("/")
bad = 0
for p in sorted(glob.glob("schema/*/*.schema.json")):
    ver = p.split("/")[1]
    expected = f"{base.rsplit('/', 1)[0]}/{ver}/{os.path.basename(p)}"
    try:
        got = json.load(open(p)).get("$id")
    except Exception as e:
        print(f"{p}: JSON inválido ({e})"); bad = 1; continue
    if got != expected:
        print(f"{p}: $id = {got!r}, esperado {expected!r} (SchemaURL.base em Models.swift)"); bad = 1
sys.exit(bad)
PY
