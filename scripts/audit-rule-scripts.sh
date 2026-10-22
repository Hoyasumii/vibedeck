#!/usr/bin/env bash
# Run all current registered rule scripts with the Rust runner; one verdict per rule.
# Usage: bash scripts/audit-rule-scripts.sh [output=/tmp/vibedeck-rules-audit.json]
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-/tmp/vibedeck-rules-audit.json}"
cargo build --quiet --release -p vibedeck
status=0
./target/release/vibedeck rules test --json > "$output" || status=$?
echo "Resultado em $output (exit $status)"
exit "$status"
