#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
applies '(^|/)(Sources/VibeDeckCore/(ProjectStore|Rules)\.swift|Tests/)'
run_tests RulesTests/unpromote
grep -A6 'public func deleteTopic' Sources/VibeDeckCore/ProjectStore.swift | grep -q releaseOrphanedIdeas || { echo "Sources/VibeDeckCore/ProjectStore.swift: deleteTopic não chama releaseOrphanedIdeas"; exit 1; }
