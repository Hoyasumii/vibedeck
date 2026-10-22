#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
none $RCLI '[Cc]oncurren|UserDefaults' "o CLI não pode ter opção de concorrência"
none $RMCP '[Cc]oncurren|UserDefaults' "o MCP não pode ter campo de concorrência"
m=$(grep -rnEi 'concurren' crates/vibedeck/src || true)
[ -z "$m" ] || { echo "o CLI/MCP não deve passar limite de concorrência ao Core:"; echo "$m"; bad=1; }
finish
