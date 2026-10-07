#!/usr/bin/env bash
# Builds build/VibeDeck.app (SwiftUI app + bundled `vibedeck` CLI).
#   scripts/build-app.sh                 release build
#   scripts/build-app.sh --install-cli   also symlinks the CLI into ~/.local/bin
#   CONFIG=debug scripts/build-app.sh    debug build
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

CONFIG="${CONFIG:-release}"
VERSION="$(grep -m1 'version: "' Sources/vibedeck/CLI.swift | sed -E 's/.*version: "([^"]+)".*/\1/')"
echo "→ swift build -c $CONFIG ${SDKROOT:+(SDK: $(basename "$SDKROOT"))}"
swift build -c "$CONFIG" --product VibeDeckApp
swift build -c "$CONFIG" --product vibedeck
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/VibeDeck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/VibeDeckApp" "$APP/Contents/MacOS/VibeDeck"
cp "$BIN/vibedeck" "$APP/Contents/Helpers/vibedeck"
# SwiftPM resource bundles (MarkdownUI etc.), if any.
find "$BIN" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>VibeDeck</string>
  <key>CFBundleDisplayName</key><string>VibeDeck</string>
  <key>CFBundleIdentifier</key><string>dev.vibedeck.app</string>
  <key>CFBundleExecutable</key><string>VibeDeck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "✓ $APP"

if [[ "${1:-}" == "--install-cli" ]]; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$PWD/$APP/Contents/Helpers/vibedeck" "$HOME/.local/bin/vibedeck"
  echo "✓ CLI: ~/.local/bin/vibedeck → $APP/Contents/Helpers/vibedeck"
fi
