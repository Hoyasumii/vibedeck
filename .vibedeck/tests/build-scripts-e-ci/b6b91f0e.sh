#!/usr/bin/env bash
# Package.swift (só o app): macOS 26, tools 6.2, produto VibeDeckApp, deps markdown-ui e SwiftTerm 1.11.x; o Core é Rust (workspace Cargo)
# sem CLI/UI/Swift: vibedeck-core não depende de clap nem do crate vibedeck.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -Eq '^(Package\.swift|Cargo\.toml|crates/[^/]+/Cargo\.toml)$'; then exit 77; fi

fail=0
bad() { echo "$1"; fail=1; }
P=Package.swift

head -1 "$P" | grep -Eq '^// swift-tools-version: *6\.2$' || bad "$P:1: swift-tools-version deve ser 6.2"
grep -q 'platforms: \[\.macOS(\.v26)\]' "$P" || bad "$P: platforms deve ser [.macOS(.v26)]"

products=$(grep -Eo '^\s*\.(executable|library)\(name: "[^"]+"' "$P" | sed -E 's/.*name: "([^"]+)"/\1/' | LC_ALL=C sort | tr '\n' ' ')
[ "$products" = "VibeDeckApp " ] || bad "$P: o único produto deve ser VibeDeckApp (CLI/MCP/Core vivem em crates/); achei: $products"

deps=$(grep -n '^\s*\.package(url:' "$P" | sed -E 's/.*\/([^\/]+)\.git".*/\1/' | LC_ALL=C sort | tr '\n' ' ')
[ "$deps" = "SwiftTerm swift-markdown-ui " ] || bad "$P: dependências permitidas: swift-markdown-ui e SwiftTerm; achei: $deps"
grep -Eq 'SwiftTerm\.git", *\.upToNextMinor\(from: "1\.11\.[0-9]+"\)' "$P" || bad "$P: SwiftTerm deve estar fixado em .upToNextMinor(from: \"1.11.x\")"
grep -q 'name: "VibeDeckApp"' "$P" || bad "$P: alvo VibeDeckApp não encontrado"
[ ! -d Sources/VibeDeckCore ] && [ ! -d Sources/vibedeck ] || bad "Sources/VibeDeckCore ou Sources/vibedeck voltou: o Core/CLI/MCP vivem em crates/"

# Workspace Cargo: Core e CLI/MCP.
C=Cargo.toml
grep -Eq '^members = \["crates/vibedeck-core", "crates/vibedeck"\]' "$C" || bad "$C: members deve ser crates/vibedeck-core e crates/vibedeck"
grep -Eq '^edition = "2024"' "$C" || bad "$C: edition deve ser 2024"
core=crates/vibedeck-core/Cargo.toml
grep -Eq '^\s*(clap|vibedeck)\s*=' "$core" && bad "$core: vibedeck-core não pode depender de clap nem do crate vibedeck (CLI/MCP ficam fora do Core)"
grep -Eq '^\s*vibedeck-core\s*=' crates/vibedeck/Cargo.toml || bad "crates/vibedeck/Cargo.toml: o CLI deve depender de vibedeck-core"
hits=$(grep -rnE '^\s*use (clap|crate::cli|crate::mcp)\b' crates/vibedeck-core/src || true)
[ -z "$hits" ] || { echo "$hits" | sed 's/$/  <- Core não pode importar isto/'; fail=1; }

exit $fail
