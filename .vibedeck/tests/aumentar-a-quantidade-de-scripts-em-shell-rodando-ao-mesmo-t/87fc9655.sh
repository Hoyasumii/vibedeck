#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
m=$(grep -rn 'UserDefaults' crates/vibedeck/src || true)
[ -z "$m" ] || { echo "o CLI/MCP não pode referenciar UserDefaults:"; echo "$m"; bad=1; }
finish
