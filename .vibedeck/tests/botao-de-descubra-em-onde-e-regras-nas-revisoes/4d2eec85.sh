#!/usr/bin/env bash
set -euo pipefail
# O Descubra só adiciona tópicos de regras ao item; nunca remove um tópico já marcado.
source "$(dirname "$0")/_lib.sh"
applies
# Em todo o código do Descubra, item.rules só pode ser lido ou receber append.
for f in "$CORE" "$APP"; do
  forbid "$f" '(item|\$0)\.rules(\.(remove|removeAll|removeFirst|removeLast|popLast|filter|replace|insert)| *= |\[[^]]*\] *=)' "o Descubra não pode remover/trocar tópicos de item.rules (só append)"
done
forbid_rs 'item\.rules\.(remove|retain|clear|truncate|drain|insert|swap_remove|pop)\(|item\.rules *= ' "o Descubra (Core Rust) não pode remover/trocar tópicos de item.rules (só push)"
apply=$(body "$CORE" 'func apply\(fields')
printf '%s\n' "$apply" | grep 'item\.rules\.append(' >/dev/null || { echo "$CORE: apply deve adicionar tópicos com item.rules.append"; fail=1; }
printf '%s\n' "$apply" | grep '!item\.rules\.contains(' >/dev/null || { echo "$CORE: apply deve pular tópicos já ligados"; fail=1; }
rapply=$(body "$RS" '    pub fn apply\(')
printf '%s\n' "$rapply" | grep 'item\.rules\.push(' >/dev/null || { echo "$RS: apply deve adicionar tópicos com item.rules.push"; fail=1; }
printf '%s\n' "$rapply" | grep '!item\.rules\.contains(' >/dev/null || { echo "$RS: apply deve pular tópicos já ligados"; fail=1; }
rtest substituir_exige_opt_in_e_topicos_so_somam
finish
