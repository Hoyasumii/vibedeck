#!/usr/bin/env bash
# O $id de cada schema/v1/<nome>.schema.json é exatamente SCHEMA_BASE + "/<nome>.schema.json".
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^schema/|^crates/vibedeck-core/src/model/project\.rs$'; then exit 77; fi
python3 -I - <<'PY'
import re, sys, glob, json, os
m = re.search(r'pub const SCHEMA_BASE:\s*&str\s*=\s*"([^"]+)"', open("crates/vibedeck-core/src/model/project.rs").read())
if not m:
    print("crates/vibedeck-core/src/model/project.rs: SCHEMA_BASE não encontrado"); sys.exit(1)
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
        print(f"{p}: $id = {got!r}, esperado {expected!r} (SCHEMA_BASE em crates/vibedeck-core/src/model/project.rs)"); bad = 1
sys.exit(bad)
PY
