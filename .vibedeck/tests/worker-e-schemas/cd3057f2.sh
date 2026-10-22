#!/usr/bin/env bash
# O índice do worker, os nomes de schema usados pelo Core Rust (schema_url), a linha "Schemas:" do guia de referência
# (crates/vibedeck-core/src/ai/guide_reference.md → .vibedeck/guide.md; o AGENTS.md compacto não a repete), o SchemaURL do app
# e os arquivos de schema/v1 listam o mesmo conjunto de schemas.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^(worker|schema)/|^crates/vibedeck-core/src/(model/|ai/guide_reference\.md)|^Sources/VibeDeckApp/Core/Model/Models\.swift$|^\.vibedeck/guide\.md$'; then exit 77; fi
python3 -I - <<'PY'
import re, sys, glob, os
sets = {}
idx = open("worker/src/index.ts").read()
m = re.search(r'schemas:\s*\{(.*?)\n\s*\},', idx, re.S)
sets["worker/src/index.ts (índice)"] = set(re.findall(r'\$\{base\}/([\w-]+)\.schema\.json', m.group(1) if m else ""))
# Nomes passados a schema_url("...") no Core (persona.rs recebe o nome por macro: agent/command/skill).
used = set()
for f in glob.glob("crates/**/*.rs", recursive=True):
    if "/tests/" in f: continue
    used |= set(re.findall(r'schema_url\("([\w-]+)"\)', open(f).read()))
used |= set(re.findall(r'^\s*\w+,\s*\w+,\s*"\w+",\s*"([\w-]+)";', open("crates/vibedeck-core/src/model/persona.rs").read(), re.M))
sets["crates/vibedeck-core (schema_url)"] = used
swift = open("Sources/VibeDeckApp/Core/Model/Models.swift").read()
m = re.search(r'enum SchemaURL\s*\{(.*?)\n\}', swift, re.S)
sets["Sources/VibeDeckApp/Core/Model/Models.swift (SchemaURL)"] = set(re.findall(r'\\\(base\)/([\w-]+)\.schema\.json', m.group(1) if m else ""))
for f in ["crates/vibedeck-core/src/ai/guide_reference.md", ".vibedeck/guide.md"]:
    m = re.search(r'Schemas:\s*\S*/\{([^}]*)\}\.schema\.json', open(f).read())
    sets[f + ' (linha "Schemas:")'] = {x.strip() for x in m.group(1).split(",")} if m else set()
sets["schema/v1/*.schema.json"] = {os.path.basename(p)[:-len(".schema.json")] for p in glob.glob("schema/v1/*.schema.json")}
union = set().union(*sets.values())
bad = 0
for name, s in sets.items():
    if not s:
        print(f"{name}: lista de schemas não encontrada"); bad = 1; continue
    if s != union:
        print(f"{name}: faltam {sorted(union - s)}"); bad = 1
# Chaves do índice batem com os nomes do SchemaURL do app (camelCase do arquivo).
keys = dict(re.findall(r'(\w+):\s*`\$\{base\}/([\w-]+)\.schema\.json`', idx))
app = dict(re.findall(r'static let (\w+)\s*=\s*"\\\(base\)/([\w-]+)\.schema\.json"', swift))
if keys != app:
    print(f"worker/src/index.ts: chaves do índice {sorted(keys.items())} ≠ SchemaURL do app {sorted(app.items())}"); bad = 1
sys.exit(bad)
PY
