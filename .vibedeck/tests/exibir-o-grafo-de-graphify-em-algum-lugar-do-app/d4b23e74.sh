#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
for k in confidence relation _origin source_file; do
  grep -q "$k" $G $PG || bad "$G:1" "tipo/confiança/origem do grafo ('$k') não é lido nem exibido pelo app"
done
need $PG 'sourceURL' "resolução segura de origem ausente"
grep -qE 'EXTRACTED|INFERRED|AMBIGUOUS' $G $PG || bad "$G:1" "relações estruturais/inferidas/ambíguas não são diferenciadas pelo app"
exit $fail
