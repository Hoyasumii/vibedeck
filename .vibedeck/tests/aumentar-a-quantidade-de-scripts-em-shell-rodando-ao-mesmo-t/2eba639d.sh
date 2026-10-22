#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'pub concurrency: Option<usize>,' "o limite deve ser um parâmetro opcional do Core"
none $EXEC 'ruleScriptConcurrency|configuredConcurrency' "o Core não pode conhecer a chave do limite"
m=$(grep -rnE 'UserDefaults|AppStorage|ruleScriptConcurrency' crates --include=*.rs || true)
[ -z "$m" ] || { echo "o Rust não pode ler a configuração do app para o limite:"; echo "$m"; bad=1; }
finish
