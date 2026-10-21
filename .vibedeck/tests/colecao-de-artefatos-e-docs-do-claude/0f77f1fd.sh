#!/usr/bin/env bash
# Todo item tem tipo (artefato/doc) visível na lista, e a lista filtra por tipo.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/|^Tests/'
fail=0
bad() { echo "$1"; fail=1; }
V=Sources/VibeDeckApp/ClaudeItemsView.swift
I=Sources/VibeDeckCore/ClaudeItem.swift
grep -q 'case artifact, doc' "$I" || bad "$I: ClaudeItemKind deve ter artifact e doc"
grep -q 'public var kind: ClaudeItemKind$' "$I" || bad "$I: ClaudeItem.kind deve ser não-opcional"
grep -q 'TableColumn("Tipo")' "$V" || bad "$V: tabela sem coluna Tipo"
grep -A2 'TableColumn("Tipo")' "$V" | grep  'item.kind.title' >/dev/null || bad "$V: coluna Tipo não mostra item.kind.title"
grep -q 'item.kind == kind' "$V" || bad "$V: lista não filtra por tipo"
grep -q 'ClaudeItemKind?.some(.artifact)' "$V" && grep -q 'ClaudeItemKind?.some(.doc)' "$V" || bad "$V: seletor de tipo sem Artefatos/Docs"
grep -q 'var kind: ClaudeItemKind?' Sources/vibedeck/CLI.swift || bad "CLI claude list: falta filtro --kind"
[ $fail -eq 0 ] || exit 1
