#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$CAT" 'id: "manutencao"' "kit de manutenção ausente"
need "$CAT" 'id: "novas-ferramentas"' "kit de novas ferramentas ausente"
n=$(grep -cE '^[[:space:]]*(makeKit|\[?[[:space:]]*makeKit)\(id:' "$CAT" || true)
[ "$n" -ge 2 ] || { echo "$CAT: esperado ao menos 2 kits via makeKit (achei $n)"; fail=1; }
for k in agent command skill workflow; do need "$CAT" "item\(\.$k," "makeKit deve gerar item do tipo $k"; done
need "$CORET" 'KitItemKind\.allCases' "teste que conta tipos por kit ausente"
finish
