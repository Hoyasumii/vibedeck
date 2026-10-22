#!/usr/bin/env bash
# A política compartilhada deve manter as cláusulas que impedem economia de dispensar verificações (Core Rust e app).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
fail=0
for f in "$POLICY" "$APP_POLICY"; do
  for p in 'Preserve requisitos' 'regras e etapas explícitas do workflow' 'tarefas simples não exigem subagentes' \
           'Não dispense validações obrigatórias' 'ausência de evidência nunca é aprovação'; do
    grep -qF "$p" "$f" || { echo "$f: cláusula ausente: $p"; fail=1; }
  done
done
exit $fail
