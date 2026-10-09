#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
exec python3 -I .vibedeck/tests/painel-lateral-melhorado/check.py 5e0c4b04
