#!/usr/bin/env bash
# Diagnóstico: nível Info disponível e filtro pelo id de correlação.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckApp/DiagnosticsView\.swift$|^Sources/VibeDeckCore/Logging\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
D=Sources/VibeDeckApp/DiagnosticsView.swift
grep -q 'ForEach(LogLevel.allCases' "$D" || bad "$D: o filtro de nível deve oferecer todos os níveis (inclui Info)"
grep -q 'case debug, info' Sources/VibeDeckCore/Logging.swift || bad "Logging.swift: LogLevel.info ausente"
grep -q 'LoggedTextField("Id da ação", text: \$action)' "$D" || bad "$D: campo 'Id da ação' ausente"
grep -q 'action: action.isEmpty ? nil : action' "$D" || bad "$D: o filtro não repassa a ação ao LogFilter"
grep -q 'Filtrar esta ação' "$D" || bad "$D: botão 'Filtrar esta ação' ausente no detalhe"
grep -q 'if let action, entry.action != action { return false }' Sources/VibeDeckCore/Logging.swift || bad "Logging.swift: LogFilter.matches não filtra por ação"
[ $fail -eq 0 ] || exit 1
