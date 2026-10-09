#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
# O app deve levar as dependências do HTML localmente; o HTML gerado não pode referenciar CDN.
forbid $G 'https?://[a-z]' "GraphView referencia URL remota para carregar a visualização"
if [ -f graphify-out/graph.html ]; then
  l=$(grep -nE '<(script|link)[^>]+(src|href)="https?://' graphify-out/graph.html | head -1 || true)
  [ -z "$l" ] || bad "graphify-out/graph.html:${l%%:*}" "o HTML gerado depende de CDN (${l#*:}) e não funciona offline"
fi
# Deve existir cópia local da lib (vis-network) empacotada ou reescrita pelo app.
grep -rqiE 'vis-network|vis\.min' Sources || find Sources -iname '*vis*network*' | grep -q . || bad "$G:1" "nenhuma cópia local de vis-network empacotada nem reescrita do HTML para uso offline"
exit $fail
