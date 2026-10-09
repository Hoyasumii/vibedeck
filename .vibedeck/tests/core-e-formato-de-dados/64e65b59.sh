#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
applies '(^|/)(Sources/VibeDeckCore/(ProjectStore|Rules)\.swift|Tests/)'
run_tests RulesTests/reviewItemGate
grep -q "Regra nova desde o último check" Sources/VibeDeckCore/ProjectStore.swift || { echo "Sources/VibeDeckCore/ProjectStore.swift: mensagem 'Regra nova desde o último check' mudou"; exit 1; }
