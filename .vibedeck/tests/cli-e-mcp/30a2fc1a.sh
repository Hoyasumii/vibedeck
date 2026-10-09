#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -q "^Sources/vibedeck/"; then exit 77; fi
MCP=Sources/vibedeck/MCPServer.swift; CLI=Sources/vibedeck/CLI.swift
fail() { echo "$1" >&2; exit 1; }
grep -q "ensureVerified" "$MCP" || fail "$MCP: update_review_item não chama ensureVerified"
python3 -I - "$MCP" "$CLI" <<'PY'
import re, sys
mcp, cli = sys.argv[1:3]
bad = 0
m = open(mcp).read()
if re.search(r"\bforce\b", m.split("struct MCPHandler",1)[1]):
    print(f"{mcp}: --force/force não pode existir no handler MCP"); bad += 1
if re.search(r"\"force\"", m):
    print(f"{mcp}: parâmetro \"force\" no schema MCP"); bad += 1
lines = open(cli).read().split("\n")
for i, l in enumerate(lines):
    if re.search(r"status\s*==\s*\.done", l) and "ensureVerified" not in l:
        print(f"{cli}:{i+1}: caminho que muda para done sem ensureVerified na mesma linha"); bad += 1
if not any("status == .done, !force { try store.ensureVerified" in l for l in lines):
    print(f"{cli}: review set --status done não chama ensureVerified (com !force)"); bad += 1
sys.exit(1 if bad else 0)
PY
