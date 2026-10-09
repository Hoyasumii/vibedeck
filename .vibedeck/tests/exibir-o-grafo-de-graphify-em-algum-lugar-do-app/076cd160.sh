#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
# Atualização consistente: gerar em diretório temporário e só trocar graph.json+graph.html quando ambos estiverem prontos.
grep -qE 'replaceItem|moveItem|temporaryDirectory|\.staging|graphify-out\.tmp|-tmp' $G || bad "$G:1" "graphify roda direto sobre graphify-out/: falha ou cancelamento no meio pode deixar graph.json/graph.html inconsistentes (sem staging/troca atômica)"
need $G 'cancelled' "tratamento de cancelamento ausente"
forbid $G 'status == 0 *\{ *generation' "sucesso é declarado só pelo código de saída, sem validar que o HTML e o JSON estão prontos"
grep -qE 'ProjectGraph\.(load|init)|fileExists.*graph\.html' <(sed -n '/private func finish/,/^    }/p' $G) || bad "$G:1" "finish() não valida a visualização (graph.json/graph.html) antes de apresentar sucesso"
exit $fail
