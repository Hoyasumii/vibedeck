#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# Roda a suíte Rust inteira (scripts/test.sh --rust = cargo test --workspace).
applies '(^|/)(crates/|Cargo\.(toml|lock)|scripts/test\.sh)'
if ! out=$(scripts/test.sh --rust 2>&1); then
  printf '%s\n' "$out" | grep -E "FAILED|panicked|^error" | head -30
  printf '%s\n' "$out" | tail -15
  exit 1
fi
printf '%s\n' "$out" | grep -E 'test result:' | tail -3
