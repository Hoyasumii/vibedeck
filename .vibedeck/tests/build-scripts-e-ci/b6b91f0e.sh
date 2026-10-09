#!/usr/bin/env bash
# Package.swift: macOS 26, tools 6.2, três produtos, deps permitidas, SwiftTerm 1.11.x só no app, Core sem deps externas/SwiftUI.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -Eq '^(Package\.swift|Sources/VibeDeckCore/)'; then exit 77; fi

fail=0
bad() { echo "$1"; fail=1; }
P=Package.swift

head -1 "$P" | grep -Eq '^// swift-tools-version: *6\.2$' || bad "$P:1: swift-tools-version deve ser 6.2"
grep -q 'platforms: \[\.macOS(\.v26)\]' "$P" || bad "$P: platforms deve ser [.macOS(.v26)]"

products=$(grep -Eo '^\s*\.(executable|library)\(name: "[^"]+"' "$P" | sed -E 's/.*name: "([^"]+)"/\1/' | LC_ALL=C sort | tr '\n' ' ')
[ "$products" = "VibeDeckApp VibeDeckCore vibedeck " ] || bad "$P: produtos devem ser VibeDeckApp, vibedeck, VibeDeckCore; achei: $products"

deps=$(grep -n '^\s*\.package(url:' "$P" | sed -E 's/.*\/([^\/]+)\.git".*/\1/' | LC_ALL=C sort | tr '\n' ' ')
[ "$deps" = "SwiftTerm swift-argument-parser swift-markdown-ui swift-sdk " ] || bad "$P: dependências permitidas: swift-argument-parser, swift-sdk, swift-markdown-ui, SwiftTerm; achei: $deps"
grep -Eq 'SwiftTerm\.git", *\.upToNextMinor\(from: "1\.11\.[0-9]+"\)' "$P" || bad "$P: SwiftTerm deve estar fixado em .upToNextMinor(from: \"1.11.x\")"

# SwiftTerm só no app (e nos testes do app): o bloco de cada alvo não-app não pode citá-lo.
swt=$(awk '
  /\.executableTarget\(/ || /\.testTarget\(/ { t="" }
  /name: "vibedeck"/ { t="cli" }
  /name: "VibeDeckCoreTests"/ { t="coretest" }
  /\.product\(name: "SwiftTerm"/ && (t=="cli" || t=="coretest") { print FILENAME ":" FNR ": SwiftTerm só pode ser usado no app" }
' "$P")
[ -z "$swt" ] || { echo "$swt"; fail=1; }

core_line=$(grep -n '\.target(name: "VibeDeckCore"' "$P" | head -1 || true)
[ -n "$core_line" ] || bad "$P: alvo VibeDeckCore não encontrado"
echo "$core_line" | grep -q 'dependencies' && bad "$P: VibeDeckCore não pode declarar dependências"

hits=$(grep -rnE '^\s*(@_exported\s+)?import\s+(SwiftUI|AppKit|MarkdownUI|SwiftTerm|ArgumentParser|MCP)\b' Sources/VibeDeckCore || true)
[ -z "$hits" ] || { echo "$hits" | sed 's/$/  <- Core não pode importar isto/'; fail=1; }

exit $fail
