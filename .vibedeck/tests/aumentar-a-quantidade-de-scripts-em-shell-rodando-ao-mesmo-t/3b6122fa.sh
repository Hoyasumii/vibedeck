#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $SETTINGS '@AppStorage(RuleExecutionModel.concurrencyKey) private var concurrency = CoreStore.defaultScriptConcurrency' "sem valor gravado o campo deve mostrar activeProcessorCount"
hasF $SETTINGS 'in: 1...CoreStore.defaultScriptConcurrency' "o campo só pode aceitar 1...activeProcessorCount"
hasF $SETTINGS 'CoreStore.scriptConcurrency(concurrency)' "o valor exibido deve ser ajustado ao limite válido"
finish
