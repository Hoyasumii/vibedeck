#!/usr/bin/env bash
set -euo pipefail
# Campos do Onde já preenchidos não são sobrescritos sem o usuário aceitar explicitamente aquela troca.
source "$(dirname "$0")/_lib.sh"
applies
need "$CORE" 'var replaces: Bool \{ current != nil \}' "FieldChange.replaces deve ser current != nil"
need "$CORE" 'defaultFields: Set<ReviewDiscover\.Field> \{ Set\(fields\.filter \{ !\$0\.replaces \}' "defaultFields deve excluir trocas de valores preenchidos"
apply=$(body "$CORE" 'func apply\(fields')
printf '%s\n' "$apply" | grep 'where chosen.contains(change.field)' >/dev/null || { echo "$CORE: apply deve gravar só os campos escolhidos"; fail=1; }
sheet=$(body "$APP" 'struct ReviewDiscoverSheet')
printf '%s\n' "$sheet" | grep 'fields = proposal.defaultFields' >/dev/null || { echo "$APP: a sheet deve começar com só os campos vazios marcados (proposal.defaultFields)"; fail=1; }
printf '%s\n' "$sheet" | grep 'Substitui:' >/dev/null || { echo "$APP: a sheet deve avisar quando a sugestão substitui um valor"; fail=1; }
# Gêmeo no Core Rust.
need "$RS" 'self\.current\.is_some\(\)' "FieldChange::replaces deve ser current.is_some()"
need "$RS" '\.filter\(\|f\| !f\.replaces\(\)\)' "default_fields deve excluir trocas de valores preenchidos"
rapply=$(body "$RS" '    pub fn apply\(')
printf '%s\n' "$rapply" | grep 'chosen.contains(&c.field)' >/dev/null || { echo "$RS: apply deve gravar só os campos escolhidos"; fail=1; }
rtest substituir_exige_opt_in_e_topicos_so_somam
finish
