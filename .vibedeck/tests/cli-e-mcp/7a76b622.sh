#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -q "^Sources/vibedeck/"; then exit 77; fi
MCP=Sources/vibedeck/MCPServer.swift; CLI=Sources/vibedeck/CLI.swift
fail() { echo "$1" >&2; exit 1; }
grep -E "Tool\(name: \"promote_idea\".*Só faça isso quando o usuário pedir\." "$MCP" >/dev/null || fail "$MCP: descrição de promote_idea sem \"Só faça isso quando o usuário pedir.\""
# nenhum outro fluxo chama promoteIdea
n=$(grep -n "promoteIdea(" "$MCP" "$CLI" | grep -v unpromoteIdea | wc -l | tr -d " ")
[ "$n" -le 2 ] || { grep -n "promoteIdea(" "$MCP" "$CLI" | grep -v unpromoteIdea >&2; fail "promoteIdea chamado em mais de um lugar por ferramenta/subcomando (esperado: 1 no MCP e 1 no CLI)"; }
