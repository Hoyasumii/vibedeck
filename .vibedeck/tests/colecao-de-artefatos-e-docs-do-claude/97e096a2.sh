#!/usr/bin/env bash
# A coleção do Claude só recebe o que o usuário adiciona: sem importação automática, sem rede.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/|^Tests/'
fail=0
bad() { echo "$1"; fail=1; }
I=Sources/VibeDeckCore/ClaudeItem.swift
V=Sources/VibeDeckApp/ClaudeItemsView.swift
# Nenhum acesso a rede/processo nos arquivos da coleção.
for f in "$I" "$V"; do
  grep -nE 'URLSession|URLRequest|Process\(|api\.anthropic|\.data\(from' "$f" && bad "$f: a coleção não pode buscar/importar itens sozinha"
done
# Só estes pontos acrescentam à coleção: addClaudeItem (CLI/MCP, pedido explícito) e o editor do app.
bad_hits=$(grep -rnE 'claude\.append' Sources --include=*.swift | grep -vE '^Sources/VibeDeckCore/ClaudeItem\.swift|^Sources/VibeDeckApp/(ClaudeItemsView|LinksView)\.swift' || true)
[ -z "$bad_hits" ] || bad "escrita na coleção fora dos pontos de adição do usuário: $bad_hits"
# Colar um link só abre o editor (não adiciona direto), e o tipo precisa ser escolhido pelo usuário.
grep -A12 'onPasteCommand' "$V" | grep  'editing = ClaudeItem' >/dev/null || bad "$V: colar link deve apenas abrir o editor"
grep -A12 'onPasteCommand' "$V" | grep  'claude.append' >/dev/null && bad "$V: colar link não pode adicionar direto"
grep -q 'kind = isNew ? nil' "$V" || bad "$V: novo item deve começar sem tipo escolhido"
grep -q 'disabled(normalized == nil)' "$V" || bad "$V: Adicionar deve exigir dados válidos"
# CLI e MCP: add exige --kind/url explícitos.
grep -A8 'struct Add: ParsableCommand' Sources/vibedeck/CLI.swift | grep  'var kind: ClaudeItemKind$' >/dev/null || bad "CLI claude add: --kind deve ser obrigatório"
[ $fail -eq 0 ] || exit 1
run_tests ClaudeItemsTests/localCollectionRoundTripAndRemoval
