#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 1) nenhuma lista paralela de ids fora de Patterns.swift: id novo em qualquer lugar, ou 2+ ids do catálogo entre aspas na mesma linha
py <<'PY' || fail=1
import _catalog as c, glob, os, re, sys
ids = [t["id"] for t in c.load()]; new = set(os.environ["NEW_IDS"].split()); bad = []
for f in sorted(glob.glob("Sources/**/*.swift", recursive=True)):
    if f == os.environ["PAT"]: continue
    for n, line in enumerate(open(f, encoding="utf-8"), 1):
        found = {i for i in ids if f'"{i}"' in line}
        if found & new or len(found) >= 2: bad.append(f"{f}:{n}: lista/id de padrão fora de Patterns.swift: {sorted(found)}")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
# 2) CLI e MCP leem de PatternCatalog
need Sources/vibedeck/CLI.swift 'PatternCatalog\.search' "CLI patterns catalog não usa PatternCatalog.search"
need Sources/vibedeck/MCPServer.swift 'PatternCatalog\.search' "MCP pattern_catalog não usa PatternCatalog.search"
# 3) resultados reais de CLI e MCP
build_cli
tmp=$(mktemp)
.build/debug/vibedeck patterns catalog --json > "$tmp"
VD_CLI="$tmp" py <<'PY' || fail=1
import _catalog as c, json, os, sys
want = os.environ["NEW_IDS"].split()
cli = {t["id"] for t in json.load(open(os.environ["VD_CLI"]))}
mcp = {t["id"] for t in json.loads(c.mcp_calls([("pattern_catalog", {})])[0])}
bad = [f"CLI sem {i}" for i in want if i not in cli] + [f"MCP sem {i}" for i in want if i not in mcp]
if cli != mcp: bad.append(f"CLI e MCP divergem: {sorted(cli ^ mcp)}")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
rm -f "$tmp"
finish
