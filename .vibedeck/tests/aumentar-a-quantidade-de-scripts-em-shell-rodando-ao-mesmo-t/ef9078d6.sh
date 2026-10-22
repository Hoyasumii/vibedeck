#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'g.running -= 1;' "a vaga deve ser liberada ao fim do script"
hasF $EXEC 'g.busy.remove(k);' "a trava da ferramenta deve ser liberada ao fim do script"
before $EXEC 'runner\.run\(&job\.command' 'g\.running -= 1' "a liberação deve vir depois do runner"
m=$(awk '/runner\.run\(&job\.command/{f=1} /g\.running -= 1/{f=0} f' $EXEC | grep -E 'return|break|continue|\?;' || true)
[ -z "$m" ] || { echo "$EXEC: saída antecipada entre o runner e a liberação: $m"; bad=1; }
finish
