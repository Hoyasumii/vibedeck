#!/usr/bin/env bash
# Índice do worker, SchemaURL (Models.swift), linha "Schemas:" do guia (AgentsGuide.swift / .vibedeck/AGENTS.md)
# e os arquivos de schema/v1 listam o mesmo conjunto de schemas.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -qE '^(worker|schema)/|^Sources/VibeDeckCore/(Models|AgentsGuide)\.swift$|^\.vibedeck/AGENTS\.md$'; then exit 77; fi
python3 -I - <<'PY'
import re, sys, glob, os
sets = {}
idx = open("worker/src/index.ts").read()
m = re.search(r'schemas:\s*\{(.*?)\n\s*\},', idx, re.S)
sets["worker/src/index.ts (índice)"] = set(re.findall(r'\$\{base\}/([\w-]+)\.schema\.json', m.group(1) if m else ""))
models = open("Sources/VibeDeckCore/Models.swift").read()
m = re.search(r'enum SchemaURL\s*\{(.*?)\n\}', models, re.S)
sets["Sources/VibeDeckCore/Models.swift (SchemaURL)"] = set(re.findall(r'\\\(base\)/([\w-]+)\.schema\.json', m.group(1) if m else ""))
for f in ["Sources/VibeDeckCore/AgentsGuide.swift", ".vibedeck/AGENTS.md"]:
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
# Chaves do índice batem com os nomes do SchemaURL (camelCase do arquivo).
keys = dict(re.findall(r'(\w+):\s*`\$\{base\}/([\w-]+)\.schema\.json`', idx))
swift = dict(re.findall(r'static let (\w+)\s*=\s*"\\\(base\)/([\w-]+)\.schema\.json"', models))
if keys != swift:
    print(f"worker/src/index.ts: chaves do índice {sorted(keys.items())} ≠ SchemaURL {sorted(swift.items())}"); bad = 1
sys.exit(bad)
PY
