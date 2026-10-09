#!/usr/bin/env bash
# Verificação estática do build-app.sh (não compila: leva minutos). Confere layout do .app, Info.plist, DMG, --install-cli e build/ ignorado.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf '%s\n' "$VIBEDECK_FILES" | grep -Eq '^(scripts/(build-app|env)\.sh|assets/|\.gitignore)'; then exit 77; fi

fail=0
B=scripts/build-app.sh
chk() { grep -Fq -- "$2" "$B" || { echo "$B: esperado '$2' ($1)"; fail=1; }; }

[ -x "$B" ] || { echo "$B: não é executável"; fail=1; }
chk "app" 'APP="build/VibeDeck.app"'
chk "app" 'cp "$BIN/VibeDeckApp" "$APP/Contents/MacOS/VibeDeck"'
chk "CLI embutido" 'cp "$BIN/vibedeck" "$APP/Contents/Helpers/vibedeck"'
chk "bundles SwiftPM" '-name '"'"'*.bundle'"'"' -exec cp -R {} "$APP/Contents/Resources/"'
chk "ícone" 'cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"'
chk "Info.plist" '$APP/Contents/Info.plist'
chk "versão no plist" '<key>CFBundleShortVersionString</key><string>$VERSION</string>'
chk "versão do CLI" 'Sources/vibedeck/CLI.swift'
chk "DMG" 'DMG="build/VibeDeck-$VERSION.dmg"'
chk "install-cli" '--install-cli'
chk "symlink" '$HOME/.local/bin/vibedeck'
chk "symlink" 'ln -sf'

grep -Eq '^build/$' .gitignore || { echo ".gitignore: falta build/"; fail=1; }
tracked=$(git ls-files build | head -3 || true)
[ -z "$tracked" ] || { echo "build/ não deve ser versionado: $tracked"; fail=1; }
for a in assets/AppIcon.icns assets/dmg-background.tiff; do [ -f "$a" ] || { echo "$a: ausente (usado pelo build-app.sh)"; fail=1; }; done
exit $fail
