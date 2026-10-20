#!/usr/bin/env bash
# Logs nunca guardam conteúdo: nenhuma chave de contexto/mensagem de conteúdo nas chamadas VDLog.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
calls=$(grep -rnE 'VDLog\.(debug|info|warning|error|log|withAction)\(' Sources --include='*.swift' | grep -v 'Sources/VibeDeckCore/Logging.swift' || true)
# Chaves de contexto proibidas.
printf '%s\n' "$calls" | grep -E '"(text|content|body|prompt|args|arguments|input|request|answer|feedback|command_line|stdout|stderr|output)"\s*:' | while IFS= read -r l; do echo "${l%%:*}: chave de contexto que sugere conteúdo: ${l#*:}"; done > /tmp/vd_0ef_$$.txt || true
# Interpolação de variáveis de conteúdo na mensagem do log.
printf '%s\n' "$calls" | grep -E '\\\((text|content|body|prompt|arguments|args|markdown|output|stderr|stdout)\b' >> /tmp/vd_0ef_$$.txt || true
[ ! -s /tmp/vd_0ef_$$.txt ] || { cat /tmp/vd_0ef_$$.txt; fail=1; }
rm -f /tmp/vd_0ef_$$.txt
# MCP: só nome e duração, nunca os argumentos.
grep -A3 'mcp.tool_called' Sources/vibedeck/MCPServer.swift | grep -q 'params.arguments' && bad "MCPServer.swift: argumentos da ferramenta não podem ir para o log"
# O LogEntry trunca campos; o teste do núcleo prova que o texto do doc fica fora do .jsonl.
grep -q 'static let maxField' Sources/VibeDeckCore/Logging.swift || bad "Logging.swift: truncamento de campos ausente"
[ $fail -eq 0 ] || exit 1
run_tests LoggingTests/editingLogsMetadataWithoutDocumentContent LoggingTests/sanitizesLongFieldsAndContext
