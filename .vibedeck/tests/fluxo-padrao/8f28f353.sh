#!/usr/bin/env bash
# Itens de revisão continuam listáveis por status, mostrando o alvo, no CLI (review list --status open)
# e no MCP (list_review_items status=open).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/vibedeck/|^Sources/VibeDeckCore/(Models|ProjectStore)\.swift$'
build_cli
new_project
fail=0

open_id=$("$VD" review add Area "Item aberto" --kind fix --file Sources/Alvo/Aberto.swift | cut -f1)
busy_id=$("$VD" review add Area "Item em andamento" --kind fix --file Sources/Alvo/Andamento.swift | cut -f1)
"$VD" review set "$busy_id" --status in_progress >/dev/null

# CLI, JSON e texto.
json=$("$VD" review list --status open --json 2>&1) || { echo "Sources/vibedeck/CLI.swift: 'review list --status open --json' falhou: $json"; exit 1; }
printf '%s' "$json" | grep -q "$open_id" || { echo "Sources/vibedeck/CLI.swift: review list --status open não lista o item aberto"; fail=1; }
printf '%s' "$json" | grep -q "$busy_id" && { echo "Sources/vibedeck/CLI.swift: review list --status open lista item in_progress"; fail=1; }
printf '%s' "$json" | grep -q 'Sources/Alvo/Aberto.swift' || { echo "Sources/vibedeck/CLI.swift: review list --json não mostra o alvo (target.file)"; fail=1; }
text=$("$VD" review list --status open)
printf '%s' "$text" | grep -q 'Sources/Alvo/Aberto.swift' || { echo "Sources/vibedeck/CLI.swift: review list (texto) não mostra o alvo do item"; fail=1; }
"$VD" review list --status in_progress --json | grep -q "$busy_id" || { echo "Sources/vibedeck/CLI.swift: review list --status in_progress não lista o item"; fail=1; }

# MCP.
c2=$(call 2 list_review_items '{"status":"open"}')
out=$(mcp '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "$c2")
printf '%s' "$(printf '%s\n' "$out" | response 1)" | grep -q '"name":"list_review_items"' || { echo "Sources/vibedeck/MCPServer.swift: ferramenta list_review_items sumiu"; exit 1; }
res=$(printf '%s\n' "$out" | response 2)
printf '%s' "$res" | grep -q '"isError":true' && { echo "Sources/vibedeck/MCPServer.swift: list_review_items status=open falhou: $res"; exit 1; }
printf '%s' "$res" | grep -q "$open_id" || { echo "Sources/vibedeck/MCPServer.swift: list_review_items status=open não lista o item aberto"; fail=1; }
printf '%s' "$res" | grep -q "$busy_id" && { echo "Sources/vibedeck/MCPServer.swift: list_review_items status=open lista item in_progress"; fail=1; }
printf '%s' "$res" | grep -q 'Sources\\\?/Alvo\\\?/Aberto.swift' || { echo "Sources/vibedeck/MCPServer.swift: list_review_items não devolve o alvo (target.file)"; fail=1; }

exit $fail
