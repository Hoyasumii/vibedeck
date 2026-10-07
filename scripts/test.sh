#!/usr/bin/env bash
# Runs the Core test suite. Built against the default SDK (Swift Testing's macro plugin ships with
# CLT), building only the test target so the SwiftUI app doesn't need to compile here.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --target VibeDeckCoreTests
swift test --skip-build "$@"
