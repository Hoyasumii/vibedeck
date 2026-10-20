#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $SETTINGS '@AppStorage(RuleExecutionModel.concurrencyKey) private var concurrency = ProjectStore.defaultScriptConcurrency' "sem valor gravado o campo deve mostrar activeProcessorCount"
hasF $SETTINGS 'in: 1...ProjectStore.defaultScriptConcurrency' "o campo só pode aceitar 1...activeProcessorCount"
hasF $SETTINGS 'ProjectStore.scriptConcurrency(concurrency)' "o valor exibido deve ser ajustado ao limite válido"
finish
