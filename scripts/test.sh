#!/usr/bin/env bash
# Testes do projeto: Core Rust (cargo) e, no macOS, os testes da interface (SwiftPM).
#   scripts/test.sh            Rust + app (app só no macOS)
#   scripts/test.sh --rust     só o Core Rust
#   scripts/test.sh --app      só a interface (precisa do SDK do macOS)
set -euo pipefail
cd "$(dirname "$0")/.."
mode="all"
[[ "${1:-}" == "--rust" ]] && { mode="rust"; shift; }
[[ "${1:-}" == "--app" ]] && { mode="app"; shift; }

if [[ "$mode" != "app" ]]; then
  cargo test --workspace "$@"
fi
if [[ "$mode" != "rust" && "$(uname)" == "Darwin" ]]; then
  source scripts/env.sh
  # Building only the test target lets the default SDK (Swift Testing's macro plugin ships with CLT) compile the app.
  swift build --build-tests
  swift test --skip-build "$@"
fi
