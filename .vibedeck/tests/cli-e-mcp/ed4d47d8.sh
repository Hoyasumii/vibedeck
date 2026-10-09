#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -q "^Sources/vibedeck/"; then exit 77; fi
MCP=Sources/vibedeck/MCPServer.swift; CLI=Sources/vibedeck/CLI.swift
fail() { echo "$1" >&2; exit 1; }
python3 -I - "$MCP" <<'PY'
import re, sys
src = open(sys.argv[1]).read().split("\n")
bad = 0
for i, l in enumerate(src):
    if re.search(r"separator: \",\"|separatedBy: \",\"", l) and "return text.split" not in l:
        print(f"{sys.argv[1]}:{i+1}: parse de lista feito à mão; use list(\"chave\")"); bad += 1
text = "\n".join(src)
for needle in ["value.arrayValue", "JSONDecoder().decode([String].self", "split(separator: \",\")"]:
    if needle not in text: print(f"helper list(): falta {needle}"); bad += 1
sys.exit(1 if bad else 0)
PY
