#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
for s in 'ausente|Sem grafo' 'vazio|Grafo vazio' 'Carregando' 'Gerando|processamento' 'inválido|Grafo inválido' 'incompatível|Incompatível'; do
  grep -qE "$s" $G || bad "$G:1" "estado '${s%%|*}' não é distinguido na tela"
done
need $G 'ProjectGraph\.load|ProjectGraph\(' "a tela não valida o grafo (inválido/incompatível) com ProjectGraph"
need $G 'vibedeck_generated_at|generatedAt|última geração' "última geração bem-sucedida não é mostrada a partir de metadado do grafo"
forbid $G 'contentModificationDate' "atualidade inferida da data do arquivo, não de registro da última geração bem-sucedida"
exit $fail
