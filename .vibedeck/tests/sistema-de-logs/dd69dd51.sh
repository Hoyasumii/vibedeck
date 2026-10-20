#!/usr/bin/env bash
# Eventos seguem area.verbo_em_snake_case; ações usam o prefixo ui.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
# Literais de evento: VDLog.<nível>("evento", ...), VDLog.log(.nível, "evento", ...), VDLog.error(err, event: "evento").
events=$(grep -rnE 'VDLog\.(debug|info|warning|error|log)\(' Sources --include='*.swift' | grep -v 'Sources/VibeDeckCore/Logging.swift' | \
  perl -ne 'if (/^([^:]+:\d+):.*VDLog\.(?:debug|info|warning|error)\("([^"]+)"/ or /^([^:]+:\d+):.*VDLog\.log\(\.\w+,\s*"([^"]+)"/ or /^([^:]+:\d+):.*event:\s*"([^"]+)"/) { print "$1 $2\n" }')
while read -r where ev; do
  [ -n "$ev" ] || continue
  [[ "$ev" =~ ^[a-z]+\.[a-z_]+$ ]] || bad "$where: evento '$ev' fora do padrão ^[a-z]+\\.[a-z_]+\$"
done <<<"$events"
# Eventos que vêm de uma ação do usuário usam ui.
grep -q 'info("ui\.[a-z_]*"' Sources/VibeDeckCore/Logging.swift || bad "Logging.swift: withAction deve usar evento ui.*"
# Reações: prefixo da área (store/ai/rules/cli/mcp) nos eventos principais.
grep -rq '"store\.file_written"' Sources/VibeDeckCore/Logging.swift || bad "store.file_written ausente"
grep -rq '"cli\.command_completed"' Sources/vibedeck/CLI.swift || bad "cli.command_completed ausente"
grep -rq '"mcp\.tool_called"' Sources/vibedeck/MCPServer.swift || bad "mcp.tool_called ausente"
grep -rq '"rules\.script_finished"' Sources/VibeDeckCore/RuleTests.swift || bad "rules.script_finished ausente"
[ $fail -eq 0 ] || exit 1
