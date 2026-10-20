#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
none $CLI '[Cc]oncurren|UserDefaults|AppStorage' "o CLI não pode ter opção de concorrência"
none $MCP '[Cc]oncurren|UserDefaults|AppStorage' "o MCP não pode ter campo de concorrência"
none $CLI 'runRuleTests\([^)]*concurrency' "o CLI não deve passar limite ao Core"
finish
