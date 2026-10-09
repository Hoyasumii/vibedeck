#!/usr/bin/env bash
# Offline contract and context-budget regression suite; never calls a paid AI provider.
# `test-ai-efficiency.sh mcp` checks the MCP server's contract and budget against Tests/Fixtures.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
if [[ "${1:-}" == "mcp" ]]; then
    swift build --product vibedeck >/dev/null
    exec python3 -I scripts/mcp-contract.py "$(swift build --show-bin-path)/vibedeck" check Tests/Fixtures
fi
if ! output=$(swift test --filter "${1:-AIEfficiencyTests|AIRecoveryTests}" 2>&1); then
    printf '%s\n' "$output" | tail -40
    exit 1
fi
printf '%s\n' "$output" | grep -q 'Test run with [1-9][0-9]* tests*' || {
    printf '%s\n' 'Nenhum teste de eficiência foi executado.'
    exit 1
}
printf '%s\n' "$output" | tail -12
