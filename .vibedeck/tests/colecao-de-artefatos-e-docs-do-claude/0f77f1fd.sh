#!/usr/bin/env bash
# 0F77F1FD: todo item tem tipo (artefato/doc) visível na lista, e a lista filtra por tipo.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^crates/vibedeck-core/src/project/claude\.rs$|^crates/vibedeck-core/src/model/project\.rs$|^crates/vibedeck/src/(cli|mcp/tools)/project\.rs$|^Sources/VibeDeckApp/ClaudeItemsView\.swift$'
need "$MODEL" 'pub enum ClaudeItemKind' "ClaudeItemKind deve existir no Core"
need "$MODEL" 'Artifact,' "ClaudeItemKind deve ter Artifact"
need "$MODEL" 'Doc,' "ClaudeItemKind deve ter Doc"
need "$MODEL" 'pub kind: ClaudeItemKind,' "ClaudeItem.kind deve ser não-opcional"
need "$CORE" 'kind\.is_none_or\(\|k\| i\.kind == k\)' "claude::list deve filtrar por tipo"
need "$CORE" 'ClaudeItemKind::Artifact => "Artefato"' "falta o título do tipo Artefato"
need "$CORE" 'ClaudeItemKind::Doc => "Doc"' "falta o título do tipo Doc"
l=$(fn_body "$CLI" '^pub struct ClaudeList')
grep -qF 'value_parser = ["artifact", "doc"]' <<<"$l" || bad "$CLI: claude list sem filtro --kind (artifact|doc)"
grep -q 'claude::kind_title(item.kind)' "$CLI" || bad "$CLI: claude list deve mostrar o tipo de cada item"
need "$MCP" '"list_claude_items"' "tool MCP list_claude_items ausente"
need "$MCP" 'claude::list\(&ctx\.store\(\)\?, kind\)' "list_claude_items deve filtrar por kind"
grep -q 'TableColumn("Tipo")' "$VIEW" || bad "$VIEW: tabela sem coluna Tipo"
grep -A2 'TableColumn("Tipo")' "$VIEW" | grep 'item.kind.title' >/dev/null || bad "$VIEW: coluna Tipo não mostra item.kind.title"
grep -q 'item.kind == kind' "$VIEW" || bad "$VIEW: lista não filtra por tipo"
grep -q 'ClaudeItemKind?.some(.artifact)' "$VIEW" && grep -q 'ClaudeItemKind?.some(.doc)' "$VIEW" || bad "$VIEW: seletor de tipo sem Artefatos/Docs"
finish
