#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$VIEW" '@State private var selected = Set<String>\(\)' "seleção deve começar vazia"
need "$VIEW" 'disabled\(selected\.isEmpty' "botão de adicionar deve ficar desabilitado sem seleção"
need "$VIEW" 'LoggedButton\("Adicionar selecionados"' "deve haver confirmação explícita"
need "$INST" 'guard !items\.isEmpty else \{ throw' "store deve rejeitar seleção vazia"
n=$(grep -c 'onAdd(' "$VIEW" || true)
[ "$n" -eq 1 ] || { echo "$VIEW: onAdd deve ser chamado só na confirmação (encontrado $n)"; fail=1; }
grep -n 'onAdd(' "$VIEW" | grep  'selected.contains' >/dev/null || { echo "$VIEW: onAdd deve usar apenas os itens selecionados"; fail=1; }
forbid "$VIEW" 'onAppear|\.task' "catálogo não deve adicionar nada ao abrir"
need "$CORET" 'addKitItems\(\[\]\)' "teste de seleção vazia ausente"
finish
