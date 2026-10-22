#!/usr/bin/env bash
# DCD7508B: itens da coleção disponíveis no CLI e no MCP, com --json na listagem.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^crates/vibedeck-core/src/project/claude\.rs$|^crates/vibedeck-core/src/model/project\.rs$|^crates/vibedeck/src/(cli|mcp/tools)/project\.rs$|^Sources/VibeDeckApp/ClaudeItemsView\.swift$'
need "$CLI" 'Claude\(Box<ClaudeArgs>\)' "$CLI: comando 'claude' não existe"
need "$CLI" 'Claude\(a\) => run_claude' "$CLI: comando 'claude' não está registrado"
e=$(fn_body "$CLI" '^pub enum ClaudeCommand')
for s in 'List(ClaudeList)' 'Add {' 'Remove {'; do grep -qF "$s" <<<"$e" || bad "$CLI: claude precisa de list/add/remove (falta $s)"; done
l=$(fn_body "$CLI" '^pub struct ClaudeList')
grep -q 'json: bool' <<<"$l" || bad "$CLI: claude list sem --json"
grep -q 'return print_json(&items)' "$CLI" || bad "$CLI: claude list --json não imprime JSON"
for t in list_claude_items add_claude_item; do
  grep -qF "\"$t\"," "$MCP" || bad "$MCP: tool MCP $t não declarada"
done
grep -A12 '"list_claude_items"' "$MCP" | grep 'json_text(' >/dev/null || bad "$MCP: list_claude_items deve devolver JSON"
grep -A12 '"list_claude_items"' "$MCP" | grep -q '\.read_only()' || grep -A25 '"list_claude_items"' "$MCP" | grep -q '\.read_only()' || bad "$MCP: list_claude_items deve ser somente leitura"
finish
