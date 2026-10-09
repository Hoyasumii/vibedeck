#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
applies '(^|/)(Sources/VibeDeckCore/(ProjectStore|Rules)\.swift|Tests/)'
run_tests RulesTests/applicableTopics
