#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'concurrency: Int? = nil' "o limite deve ser um parâmetro opcional do Core"
none $PS 'ruleScriptConcurrency|configuredConcurrency' "o Core não pode conhecer a chave do limite"
m=$(grep -rnE 'UserDefaults|AppStorage' Sources/VibeDeckCore | grep -iE 'concurren|limite|ruleScript' || true)
[ -z "$m" ] || { echo "o Core não pode ler UserDefaults para o limite:"; echo "$m"; bad=1; }
finish
