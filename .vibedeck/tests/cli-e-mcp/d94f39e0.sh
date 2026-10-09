#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -q "^Sources/vibedeck/"; then exit 77; fi
MCP=Sources/vibedeck/MCPServer.swift; CLI=Sources/vibedeck/CLI.swift
fail() { echo "$1" >&2; exit 1; }
grep -qE "struct Unpromote" "$CLI" || fail "$CLI: subcomando ideas unpromote ausente"
grep -q "unpromoteIdea(" "$CLI" || fail "$CLI: unpromote não chama store.unpromoteIdea"
grep -qE "case \"unpromote_idea\":" "$MCP" || fail "$MCP: case unpromote_idea ausente"
grep -q "unpromoteIdea(" "$MCP" || fail "$MCP: unpromote_idea não chama store.unpromoteIdea"
grep -E "Tool\(name: \"unpromote_idea\".*Só faça isso quando o usuário pedir\." "$MCP" >/dev/null || fail "$MCP: descrição de unpromote_idea sem \"Só faça isso quando o usuário pedir.\""
