#!/usr/bin/env bash
# Itens da coleção disponíveis no CLI e no MCP, com --json na listagem.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/vibedeck/|^Sources/VibeDeckCore/|^Tests/'
fail=0
bad() { echo "$1"; fail=1; }
C=Sources/vibedeck/CLI.swift
M=Sources/vibedeck/MCPServer.swift
grep -q 'struct Claude: ParsableCommand' "$C" || bad "$C: comando 'claude' não existe"
grep -A12 'struct Claude: ParsableCommand' "$C" | grep 'List.self, Add.self, Remove.self' >/dev/null || bad "$C: claude precisa de list/add/remove"
l=$(awk '/struct Claude: ParsableCommand/{f=1} f&&/struct List: ParsableCommand/{g=1} g{print} g&&/^    }$/{exit}' "$C")
printf '%s\n' "$l" | grep '@Flag.*var json' >/dev/null || bad "$C: claude list sem --json"
printf '%s\n' "$l" | grep 'printJSON(items)' >/dev/null || bad "$C: claude list --json não imprime JSON"
grep -q 'Claude.self' "$C" || bad "$C: Claude não registrado nos subcomandos"
for t in list_claude_items add_claude_item; do
  grep -q "Tool(name: \"$t\"" "$M" || bad "$M: tool MCP $t não declarada"
  grep -q "case \"$t\":" "$M" || bad "$M: tool MCP $t sem implementação"
done
grep -A6 'case "list_claude_items":' "$M" | grep 'json(' >/dev/null || bad "$M: list_claude_items deve devolver JSON"
[ $fail -eq 0 ] || exit 1
