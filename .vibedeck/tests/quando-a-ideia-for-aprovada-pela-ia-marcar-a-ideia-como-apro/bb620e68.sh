#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# BB620E68 (should): README, .vibedeck/guide.md e o guia embutido no Core documentam Salvar avaliação + approved.
for f in README.md .vibedeck/guide.md "$GUIDE"; do
  grep 'Salvar avaliação' "$f" | grep 'approved' >/dev/null || bad "$f: falta 'Salvar avaliação' com 'approved'"
done
finish
