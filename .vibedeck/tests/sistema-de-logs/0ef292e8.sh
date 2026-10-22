#!/usr/bin/env bash
# Logs nunca guardam conteúdo: nenhuma chave de contexto/mensagem de conteúdo nas chamadas de log (app e Core Rust).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '\.(swift|rs)$'
fail=0
bad() { echo "$1"; fail=1; }
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
swift_calls=$(grep -rnE 'VDLog\.(debug|info|warning|error|log|withAction)\(' Sources --include='*.swift' | grep -v "$APPLOG" || true)
rust_calls=$(grep -rnE --include='*.rs' '(^|[^a-z_])logs::(debug|info|warning|error|log)\(' crates | grep -v "^$RUSTLOG" || true)
calls=$(printf '%s\n%s\n' "$swift_calls" "$rust_calls")
# Chaves de contexto proibidas.
printf '%s\n' "$calls" | grep -E '"(text|content|body|prompt|args|arguments|input|request|answer|feedback|command_line|stdout|stderr|output)"\s*[:,]' | while IFS= read -r l; do echo "${l%%:*}: chave de contexto que sugere conteúdo: ${l#*:}"; done > "$tmp" || true
# Interpolação de variáveis de conteúdo na mensagem do log.
printf '%s\n' "$calls" | grep -E '\\\((text|content|body|prompt|arguments|args|markdown|output|stderr|stdout)\b|format!\([^)]*\b(text|content|body|prompt|args|markdown|stdout|stderr)\b' >> "$tmp" || true
[ ! -s "$tmp" ] || { cat "$tmp"; fail=1; }
# MCP: só nome e duração, nunca os argumentos (no Rust, nenhuma chamada de log em crates/vibedeck pode citar args).
grep -rnE --include='*.rs' 'logs::(debug|info|warning|error|log)\(.*\bargs\b' crates/vibedeck/src && bad "crates/vibedeck/src/mcp: argumentos da ferramenta não podem ir para o log"
# Truncamento de campos no formato de entrada (Rust e app).
grep -q 'pub const MAX_FIELD' "$RUSTLOG" || bad "$RUSTLOG: truncamento de campos (MAX_FIELD) ausente"
grep -q 'static let maxField' "$APPLOG" || bad "$APPLOG: truncamento de campos ausente"
[ $fail -eq 0 ] || exit 1
run_tests higieniza_campos_longos
