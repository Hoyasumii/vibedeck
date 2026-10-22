#!/usr/bin/env bash
# B5B453DC: remover da coleção só altera o manifesto local: nenhuma API do Claude, nenhuma exclusão na conta.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^crates/vibedeck-core/src/project/claude\.rs$|^crates/vibedeck-core/src/model/project\.rs$|^crates/vibedeck/src/(cli|mcp/tools)/project\.rs$|^Sources/VibeDeckApp/ClaudeItemsView\.swift$'
need "$CORE" 'pub fn remove\(' "claude::remove não existe"
body=$(fn_body "$CORE" '^pub fn remove\(')
printf '%s\n' "$body" | grep -E 'reqwest|ureq|http|Command::new|DELETE|open' >/dev/null && bad "$CORE: remove não pode chamar API/rede"
printf '%s\n' "$body" | grep 'project.claude.retain' >/dev/null || bad "$CORE: remove deve apenas retirar o item do manifesto"
printf '%s\n' "$body" | grep 'store.save_project' >/dev/null || bad "$CORE: remove deve gravar o manifesto"
need "$CORE" 'AmbiguousClaudeItem' "remoção ambígua deve falhar sem alterar o manifesto"
# remove() da view: só mutateProject.
vbody=$(awk '/private func remove\(/{f=1} f{print} f&&/^    }$/{exit}' "$VIEW")
printf '%s\n' "$vbody" | grep 'mutateProject' >/dev/null || bad "$VIEW: remove deve usar mutateProject"
printf '%s\n' "$vbody" | grep -E 'URLSession|Process|openURL|DELETE|http' >/dev/null && bad "$VIEW: remove não pode chamar API/rede"
# CLI de remoção.
c=$(awk '/ClaudeCommand::Remove \{ id \}/{print; exit}' "$CLI")
printf '%s\n' "$c" | grep 'claude::remove(&store, &id)' >/dev/null || bad "$CLI: claude remove deve usar claude::remove"
finish
