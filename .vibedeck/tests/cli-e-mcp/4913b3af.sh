#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -q "^Sources/vibedeck/"; then exit 77; fi
MCP=Sources/vibedeck/MCPServer.swift; CLI=Sources/vibedeck/CLI.swift
fail() { echo "$1" >&2; exit 1; }
n=$(grep -c "version: \"" "$CLI" || true)
[ "$n" -ge 1 ] || fail "$CLI: nenhuma linha com version: \"x.y.z\""
v=$(grep -m1 "version: \"" "$CLI" | sed -E "s/.*version: \"([^\"]+)\".*/\1/")
printf "%s" "$v" | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+$" || fail "$CLI: versão \"$v\" fora do formato x.y.z"
b=$(grep -m1 "version: \"" scripts/build-app.sh >/dev/null 2>&1; sed -n "s/^VERSION=.*//p" scripts/build-app.sh)
grep -q "grep -m1 .version: \"" scripts/build-app.sh || fail "scripts/build-app.sh não lê mais a versão de CLI.swift"
d=$(grep -rn "version: \"$v\"" Sources --include=*.swift | grep -v "^$CLI" || true)
[ -z "$d" ] || fail "versão duplicada: $d"
