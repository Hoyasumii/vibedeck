#!/usr/bin/env bash
# documentação de Salvar avaliação + approved
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
for f in README.md .vibedeck/guide.md Sources/VibeDeckCore/AgentsGuide.swift; do
  grep -q 'Salvar avaliação' "$f" && grep 'Salvar avaliação' "$f" | grep 'approved' >/dev/null || { echo "$f: falta 'Salvar avaliação' com 'approved'"; exit 1; }
done
