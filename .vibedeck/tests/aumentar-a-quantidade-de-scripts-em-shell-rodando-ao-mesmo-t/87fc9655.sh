#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
none $CLI 'UserDefaults' "o CLI não pode referenciar UserDefaults"
none $MCP 'UserDefaults' "o MCP não pode referenciar UserDefaults"
finish
