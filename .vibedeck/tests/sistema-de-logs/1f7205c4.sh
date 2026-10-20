#!/usr/bin/env bash
# Ação carrega id de correlação (context["action"]); reações herdam o mesmo id.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies "$LOG_SCOPE|^Sources/VibeDeckCore/"
fail=0
bad() { echo "$1"; fail=1; }
L=Sources/VibeDeckCore/Logging.swift
grep -q 'if let action = actionID ?? config.inheritedAction { context\["action"\] = action }' "$L" || bad "$L: VDLog.log deve gravar context[action] com o id da ação"
grep -q 'UUID().uuidString' "$L" || bad "$L: withAction deve gerar id de correlação"
grep -q 'environment\["VIBEDECK_ACTION"\]' Sources/VibeDeckCore/RuleTests.swift || bad "RuleTests.swift: scripts de regra devem herdar VIBEDECK_ACTION"
# Trabalho em background (exceto leituras puras sem log: childPATH, projectFiles, LogStore.entries, CloudSession.check) mantém a correlação (VDLog.detached em vez de Task.detached).
while IFS= read -r hit; do bad "$hit: Task.detached perde o id da ação; use VDLog.detached"; done < <(grep -rn 'Task\.detached' Sources/VibeDeckApp Sources/VibeDeckCore --include='*.swift' | grep -v 'Logging.swift' | grep -vE 'childPATH\(\)|projectFiles\(root|LogStore\.default\.entries|CloudSession\.check\(' || true)
[ $fail -eq 0 ] || exit 1
run_tests LoggingTests/editingLogsMetadataWithoutDocumentContent LoggingTests/parallelActionsKeepIndependentCorrelation LoggingTests/ruleWorkersKeepActionAcrossNativeThreads LoggingTests/actionFilterIncludesOnlyItsReactions
