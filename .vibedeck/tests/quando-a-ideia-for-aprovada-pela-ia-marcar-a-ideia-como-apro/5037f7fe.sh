#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 5037F7FE: o status só muda em applyVerdict (botão Salvar avaliação); Descubra/Verificar sem salvar não alteram a ideia.
# Nenhum código do fluxo Descubra/Verificar no app escreve status direto.
if grep -nE '\.status\s*=|mutateIdea' "$RD"; then bad "$RD escreve na ideia"; fi
grep -q 'LoggedButton("Salvar avaliação") { applyVerdict(verdict) }' "$RD" || bad "$RD: botão Salvar avaliação não chama applyVerdict"
# apply é o único lugar que atribui .approved no código de domínio da avaliação.
c=$(grep -c 'status = .approved' "$LOGIC" || true)
[ "$c" = 1 ] || bad "$LOGIC: esperado 1 atribuição de approved, achei $c"
finish
