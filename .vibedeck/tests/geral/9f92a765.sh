#!/usr/bin/env bash
# Valida os JSONs do projeto contra schema/v1 (UUIDs, datas ISO 8601, enums, $schema) e roda `vibedeck status`.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
here=".vibedeck/tests/geral"

if [ -n "${VIBEDECK_FILES:-}" ]; then
  files=$(printf '%s\n' "$VIBEDECK_FILES" | grep -E '^(vibedeck\.json|\.vibedeck/(reviews|rules|ideas|agents|commands|skills|workflows)/[^/]+\.json)$' || true)
  [ -n "$files" ] || exit 77
else
  files=$(ls vibedeck.json .vibedeck/{reviews,rules,ideas,agents,commands,skills,workflows}/*.json 2>/dev/null || true)
fi

# shellcheck disable=SC2086
python3 -I "$here/_validate.py" $files || { echo "violação: JSON fora do schema (veja acima)"; exit 1; }

if command -v vibedeck >/dev/null 2>&1; then
  vibedeck status >/dev/null 2>&1 || { echo "violação: 'vibedeck status' falhou ao carregar o projeto"; exit 1; }
fi
