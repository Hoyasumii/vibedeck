#!/usr/bin/env bash
# Offline contract and context-budget regression suite; never calls a paid AI provider.
# `test-ai-efficiency.sh mcp` checks the MCP server's contract and budget against Tests/Fixtures.
# `test-ai-efficiency.sh <filter>` runs only the Rust tests whose name matches <filter>.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "mcp" ]]; then
    cargo build --release -p vibedeck >/dev/null
    exec python3 -I scripts/mcp-contract.py target/release/vibedeck check Tests/Fixtures
fi
filter="${1:-}"
run() {
    local output
    if ! output=$(cargo test --quiet "$@" 2>&1); then
        printf '%s\n' "$output" | tail -40
        exit 1
    fi
    printf '%s\n' "$output" | grep -E '^test result: ' | tail -3
    printf '%s\n' "$output" | grep -qE '^test result: ok\. [1-9][0-9]* passed' || {
        printf '%s\n' 'Nenhum teste de eficiência foi executado.'
        exit 1
    }
}
if [[ -n "$filter" ]]; then
    run --workspace -- "$filter"
    exit 0
fi
# Guide, context pages, usage/statusline, catalog (unit) and the AI items / workflows / CLI integration suites.
run -p vibedeck-core --lib -- ai::context ai::guide ai::usage ai::catalog ai::item
run -p vibedeck-core --test ai_items --test workflows_core
run -p vibedeck --test ai_cli
