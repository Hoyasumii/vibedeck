#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^(crates/vibedeck/|Cargo\.toml|scripts/build-app\.sh)"; then exit 77; fi
fail() { echo "$1" >&2; exit 1; }
n=$(grep -c '^version = "' Cargo.toml || true)
[ "$n" -eq 1 ] || fail "Cargo.toml: esperada exatamente 1 linha version = \"x.y.z\" (no [workspace.package]), achei $n"
v=$(grep -m1 '^version = "' Cargo.toml | sed -E 's/.*version = "([^"]+)".*/\1/')
printf "%s" "$v" | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+$" || fail "Cargo.toml: versão \"$v\" fora do formato x.y.z"
grep -q "^version.workspace = true" crates/vibedeck/Cargo.toml crates/vibedeck-core/Cargo.toml || fail "crates devem herdar a versão com version.workspace = true"
grep -qF "grep -m1 '^version = \"' Cargo.toml" scripts/build-app.sh || fail "scripts/build-app.sh não lê mais a versão do Cargo.toml"
d=$(grep -rnE "^version = \"$v\"" crates --include=Cargo.toml || true)
[ -z "$d" ] || fail "versão duplicada: $d"
