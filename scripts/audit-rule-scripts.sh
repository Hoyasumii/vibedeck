#!/usr/bin/env bash
# Run all current registered rule scripts; output contains one verdict per rule.
# Usage: bash scripts/audit-rule-scripts.sh [concurrency=1] [output=/tmp/vibedeck-rules-audit.json]
# Invoke separately from other SwiftPM builds/tests to avoid competing for .build.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
root="$PWD"
concurrency="${1:-1}"
output="${2:-/tmp/vibedeck-rules-audit.json}"
# Finish building before loading the test bundle: scripts can invoke SwiftPM themselves.
swift build --build-tests
bin_path="$(swift build --show-bin-path)"
export VIBEDECK_RULE_AUDIT_ROOT="$root"
export VIBEDECK_RULE_AUDIT_CONCURRENCY="$concurrency"
export VIBEDECK_RULE_AUDIT_OUTPUT="$output"
if [ "$(uname -s)" = Darwin ]; then
  swift_path="$(xcrun --find swift)"
  platform="$(xcrun --show-sdk-platform-path)"
  export DYLD_FRAMEWORK_PATH="$platform/Developer/Library/Frameworks${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
  export DYLD_LIBRARY_PATH="$platform/Developer/usr/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  exec "$(dirname "$swift_path")/../libexec/swift/pm/swiftpm-testing-helper" \
    --test-bundle-path "$bin_path/VibeDeckCoreTests.xctest/Contents/MacOS/VibeDeckCoreTests" \
    --testing-library swift-testing --filter RuleScriptAuditTests
else
  exec "$bin_path/VibeDeckCoreTests.xctest" --testing-library swift-testing --filter RuleScriptAuditTests
fi
