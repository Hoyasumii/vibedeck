#!/usr/bin/env bash
# Remover da coleção só altera o manifesto local: nenhuma API do Claude, nenhuma exclusão na conta.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/|^Tests/'
fail=0
bad() { echo "$1"; fail=1; }
I=Sources/VibeDeckCore/ClaudeItem.swift
V=Sources/VibeDeckApp/ClaudeItemsView.swift
grep -q 'func removeClaudeItem' "$I" || bad "$I: removeClaudeItem não existe"
# Corpo de removeClaudeItem: só updateProject/removeAll.
body=$(awk '/func removeClaudeItem/{f=1} f{print} f&&/^    }$/{exit}' "$I")
printf '%s\n' "$body" | grep -E 'URLSession|Process|http|DELETE|openURL' >/dev/null && bad "$I: removeClaudeItem não pode chamar API/rede"
printf '%s\n' "$body" | grep  'claude.removeAll' >/dev/null || bad "$I: removeClaudeItem deve apenas remover do manifesto"
# remove() da view: só mutateProject.
vbody=$(awk '/private func remove\(/{f=1} f{print} f&&/^    }$/{exit}' "$V")
printf '%s\n' "$vbody" | grep  'mutateProject' >/dev/null || bad "$V: remove deve usar mutateProject"
printf '%s\n' "$vbody" | grep -E 'URLSession|Process|openURL|DELETE|http' >/dev/null && bad "$V: remove não pode chamar API/rede"
# CLI e MCP de remoção.
c=$(awk '/struct Claude: ParsableCommand/{g=1} g&&/struct Remove: ParsableCommand/{f=1} f{print} f&&/^    }$/{exit}' Sources/vibedeck/CLI.swift)
printf '%s\n' "$c" | grep  'removeClaudeItem' >/dev/null || bad "CLI claude remove deve usar removeClaudeItem"
printf '%s\n' "$c" | grep -E 'URLSession|runClaude|Process' >/dev/null && bad "CLI claude remove não pode chamar o Claude"
[ $fail -eq 0 ] || exit 1
run_tests ClaudeItemsTests/localCollectionRoundTripAndRemoval ClaudeItemsTests/ambiguousRemovalDoesNotChangeManifest
