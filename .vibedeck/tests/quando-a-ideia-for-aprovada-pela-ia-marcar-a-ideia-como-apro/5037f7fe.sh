#!/usr/bin/env bash
# status só muda em applyVerdict
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Nenhum código do fluxo Descubra/Verificar no app escreve status direto
if grep -nE '\.status\s*=|mutateIdea' Sources/VibeDeckApp/RuleDiscover.swift; then echo "Sources/VibeDeckApp/RuleDiscover.swift escreve na ideia"; exit 1; fi
# Só o botão Salvar avaliação chama applyVerdict(verdict) na view
n=$(grep -c 'applyVerdict(verdict)' Sources/VibeDeckApp/RuleDiscover.swift)
grep -q 'LoggedButton("Salvar avaliação") { applyVerdict(verdict) }' Sources/VibeDeckApp/RuleDiscover.swift || { echo "botão Salvar avaliação não chama applyVerdict"; exit 1; }
# Core: apply é o único lugar que atribui .approved
c=$(grep -c 'status = .approved' Sources/VibeDeckCore/RuleDiscover.swift)
[ "$c" = 1 ] || { echo "Core RuleDiscover.swift: esperado 1 atribuição de approved, achou $c"; exit 1; }
