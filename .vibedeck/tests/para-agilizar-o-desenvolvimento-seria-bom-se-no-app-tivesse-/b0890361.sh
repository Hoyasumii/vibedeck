#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
for f in README.md .vibedeck/guide.md; do
  grep -q "Copiar prompt" "$f" || { echo "$f: sem menção ao botão \"Copiar prompt\"" >&2; exit 1; }
done
exit 0
