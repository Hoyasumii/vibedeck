#!/usr/bin/env bash
# Campos do Onde já preenchidos não são sobrescritos sem o usuário aceitar explicitamente aquela troca.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$CORE" 'public var replaces: Bool \{ current != nil \}' "FieldChange.replaces deve ser current != nil"
need "$CORE" 'defaultFields: Set<ReviewDiscover\.Field> \{ Set\(fields\.filter \{ !\$0\.replaces \}' "defaultFields deve excluir trocas de valores preenchidos"
apply=$(body "$CORE" 'public func apply\(fields')
printf '%s\n' "$apply" | grep -q 'where chosen.contains(change.field)' || { echo "$CORE: apply deve gravar só os campos escolhidos"; fail=1; }
sheet=$(body "$APP" 'struct ReviewDiscoverSheet')
printf '%s\n' "$sheet" | grep -q 'fields = proposal.defaultFields' || { echo "$APP: a sheet deve começar com só os campos vazios marcados (proposal.defaultFields)"; fail=1; }
printf '%s\n' "$sheet" | grep -q 'Substitui:' || { echo "$APP: a sheet deve avisar quando a sugestão substitui um valor"; fail=1; }
finish
run_tests ReviewDiscoverTests/replacingNeedsOptInAndTopicsOnlyAdd
