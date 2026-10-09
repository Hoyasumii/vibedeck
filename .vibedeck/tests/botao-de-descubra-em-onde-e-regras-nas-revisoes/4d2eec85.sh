#!/usr/bin/env bash
# O Descubra só adiciona tópicos de regras ao item; nunca remove um tópico já marcado.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# Em todo o código do Descubra, item.rules só pode ser lido ou receber append.
for f in "$CORE" "$APP"; do
  forbid "$f" '(item|\$0)\.rules(\.(remove|removeAll|removeFirst|removeLast|popLast|filter|replace|insert)| *= |\[[^]]*\] *=)' "o Descubra não pode remover/trocar tópicos de item.rules (só append)"
done
apply=$(body "$CORE" 'public func apply\(fields')
printf '%s\n' "$apply" | grep -q 'item\.rules\.append(' || { echo "$CORE: apply deve adicionar tópicos com item.rules.append"; fail=1; }
printf '%s\n' "$apply" | grep -q '!item\.rules\.contains(' || { echo "$CORE: apply deve pular tópicos já ligados"; fail=1; }
finish
run_tests ReviewDiscoverTests/replacingNeedsOptInAndTopicsOnlyAdd
