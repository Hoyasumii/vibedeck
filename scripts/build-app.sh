#!/usr/bin/env bash
# Builds build/VibeDeck.app (SwiftUI app + bundled `vibedeck` CLI) and the installer
# build/VibeDeck-<version>.dmg (drag VibeDeck onto the Applications shortcut).
#   scripts/build-app.sh                 release build + DMG
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
# Icon: regenerate with `swift scripts/make-icon.swift` after changing the mark.
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Terminal font: JetBrains Mono Nerd Font Mono (SIL OFL 1.1, see assets/fonts/OFL.txt).
cp -R assets/fonts "$APP/Contents/Resources/Fonts"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>VibeDeck</string>
  <key>CFBundleDisplayName</key><string>VibeDeck</string>
  <key>CFBundleIdentifier</key><string>dev.vibedeck.app</string>
  <key>CFBundleExecutable</key><string>VibeDeck</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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

DMG="build/VibeDeck-$VERSION.dmg"
STAGE="$(mktemp -d)"
RW="$STAGE.rw.dmg"
MNT="/Volumes/VibeDeck"
trap 'hdiutil detach -quiet "$MNT" 2>/dev/null || true; rm -rf "$STAGE" "$RW"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Installer window art: regenerate with `swift scripts/make-dmg-background.swift`.
mkdir "$STAGE/.background"
cp assets/dmg-background.tiff "$STAGE/.background/background.tiff"
cp assets/AppIcon.icns "$STAGE/.VolumeIcon.icns"

hdiutil detach -quiet "$MNT" 2>/dev/null || true
hdiutil create -quiet -volname "VibeDeck" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
hdiutil attach -quiet -noautoopen -mountpoint "$MNT" "$RW"
SetFile -a C "$MNT"
# Standard drag-to-install window; positions match the arrow in the background.
osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "VibeDeck"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "VibeDeck.app" of container window to {170, 180}
    set position of item "Applications" of container window to {470, 180}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "$MNT"
rm -f "$DMG"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
echo "✓ $DMG"

if [[ "${1:-}" == "--install-cli" ]]; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$PWD/$APP/Contents/Helpers/vibedeck" "$HOME/.local/bin/vibedeck"
  echo "✓ CLI: ~/.local/bin/vibedeck → $APP/Contents/Helpers/vibedeck"
fi
