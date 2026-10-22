#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# D4DD944D: nada é adicionado sem seleção explícita do usuário.
need "$VIEW" '@State private var selected = Set<String>\(\)' "seleção deve começar vazia"
need "$VIEW" 'disabled\(selected\.isEmpty' "botão de adicionar deve ficar desabilitado sem seleção"
need "$VIEW" 'LoggedButton\("Adicionar selecionados"' "deve haver confirmação explícita"
need "$KITS" 'if items\.is_empty\(\)' "o Core deve rejeitar seleção vazia"
need "$KITS" 'InvalidKitSelection\("nenhum item"' "seleção vazia deve ser erro identificado"
n=$(grep -c 'onAdd(' "$VIEW" || true)
[ "$n" -eq 1 ] || { echo "$VIEW: onAdd deve ser chamado só na confirmação (encontrado $n)"; fail=1; }
grep -n 'onAdd(' "$VIEW" | grep 'selected.contains' >/dev/null || { echo "$VIEW: onAdd deve usar apenas os itens selecionados"; fail=1; }
forbid "$VIEW" 'onAppear|\.task' "catálogo não deve adicionar nada ao abrir"
finish
