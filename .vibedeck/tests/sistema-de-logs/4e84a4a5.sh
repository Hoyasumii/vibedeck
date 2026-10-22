#!/usr/bin/env bash
# MCP expõe leitura de logs de ação (nível, período, componente, ação) além dos resources de aviso/crash.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^crates/vibedeck(-core)?/src/(mcp/|project/logs\.rs)'
fail=0
bad() { echo "$1"; fail=1; }
M=crates/vibedeck/src/mcp/tools/project.rs
tool=$(awk '/"read_logs",/ {on=1} on {print} on && /\.read_only\(\),/ {exit}' "$M")
[ -n "$tool" ] || bad "$M: ferramenta read_logs ausente"
for k in '"level"' '"since"' '"components"' '"action"'; do printf '%s' "$tool" | grep -F "prop($k" >/dev/null || printf '%s' "$tool" | grep -F "$k" >/dev/null || bad "$M: ferramenta read_logs sem o parâmetro $k"; done
printf '%s' "$tool" | grep -F '.read_only()' >/dev/null || bad "$M: read_logs deve ser somente leitura"
printf '%s' "$tool" | grep -F 'logs::read_logs(' >/dev/null || bad "$M: read_logs deve usar logs::read_logs"
printf '%s' "$tool" | grep -F 'LogStore::default_store()' >/dev/null || bad "$M: read_logs deve ler do LogStore"
grep -qF 'unwrap_or("info")' "$RUSTLOG" || bad "$RUSTLOG: read_logs deve usar info como nível padrão"
grep -qF '"vibedeck://logs" =>' "$M" || bad "$M: resource vibedeck://logs ausente"
grep -qF '"vibedeck://logs/crashes" =>' "$M" || bad "$M: resource vibedeck://logs/crashes ausente"
[ $fail -eq 0 ] || exit 1
