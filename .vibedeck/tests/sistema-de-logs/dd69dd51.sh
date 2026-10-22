#!/usr/bin/env bash
# Eventos seguem area.verbo_em_snake_case; ações usam o prefixo ui.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '\.(swift|rs)$'
fail=0
bad() { echo "$1"; fail=1; }
# Literais de evento: VDLog.<nível>("evento", ...), VDLog.log(.nível, "evento", ...), VDLog.error(err, event: "evento").
events=$(grep -rnE 'VDLog\.(debug|info|warning|error|log)\(' Sources --include='*.swift' | grep -v "$APPLOG" | \
  perl -ne 'if (/^([^:]+:\d+):.*VDLog\.(?:debug|info|warning|error)\("([^"]+)"/ or /^([^:]+:\d+):.*VDLog\.log\(\.\w+,\s*"([^"]+)"/ or /^([^:]+:\d+):.*event:\s*"([^"]+)"/) { print "$1 $2\n" }')
while read -r where ev; do
  [ -n "$ev" ] || continue
  [[ "$ev" =~ ^[a-z]+\.[a-z_]+$ ]] || bad "$where: evento '$ev' fora do padrão ^[a-z]+\\.[a-z_]+\$"
done <<<"$events"
# Core Rust: chamadas logs::info/warning/error("evento", ...) fora do módulo de logs.
rs_events=$(grep -rnE --include='*.rs' '(^|[^a-z_])logs::(info|warning|error)\(\s*"[^"]+"' crates | grep -v "^$RUSTLOG" | sed -E 's/^([^:]+:[0-9]+):.*logs::(info|warning|error)\(\s*"([^"]+)".*/\1 \3/' || true)
while read -r where ev; do
  [ -n "$ev" ] || continue
  [[ "$ev" =~ ^[a-z]+\.[a-z_]+$ ]] || bad "$where: evento '$ev' fora do padrão ^[a-z]+\\.[a-z_]+\$"
done <<<"$rs_events"
# Eventos que vêm de uma ação do usuário usam ui.
grep -q 'info("ui\.[a-z_]*"' "$APPLOG" || bad "$APPLOG: withAction deve usar evento ui.*"
# Reações: prefixo da área (store/ai/rules/cli/mcp) nos eventos principais.
grep -q '"store\.file_written"' "$APPLOG" || bad "store.file_written ausente"
grep -rq '"rules\.script_finished"' Sources/VibeDeckApp/Core/Model/RuleTests.swift || bad "rules.script_finished ausente"
# (cli.command_completed e mcp.tool_called no Rust são cobertos pela regra de logs de CLI/MCP.)
[ $fail -eq 0 ] || exit 1
