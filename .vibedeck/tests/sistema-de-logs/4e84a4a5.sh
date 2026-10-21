#!/usr/bin/env bash
# MCP expõe leitura de logs de ação (nível, período, componente, ação) além dos resources de aviso/crash.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/vibedeck/MCPServer\.swift$|^Sources/VibeDeckCore/Logging\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
M=Sources/vibedeck/MCPServer.swift
tool=$(grep -A5 'Tool(name: "read_logs"' "$M")
for k in '"level"' '"since"' '"components"' '"action"'; do printf '%s' "$tool" | grep  "$k" >/dev/null || bad "$M: ferramenta read_logs sem o parâmetro $k"; done
printf '%s' "$tool" | grep  'readOnlyHint: true' >/dev/null || bad "$M: read_logs deve ser somente leitura"
call=$(grep -A7 'case "read_logs":' "$M")
printf '%s' "$call" | grep  'parseLevel(str("level") ?? "info")' >/dev/null || bad "$M: read_logs deve usar info como nível padrão"
printf '%s' "$call" | grep  'LogStore.default.entries' >/dev/null || bad "$M: read_logs deve ler do LogStore"
grep -q 'uri == "vibedeck://logs"' "$M" || bad "$M: resource vibedeck://logs ausente"
[ $fail -eq 0 ] || exit 1
