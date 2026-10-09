#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
exec python3 -I .vibedeck/tests/melhorar-o-md-viewer/check.py ADA320A2
