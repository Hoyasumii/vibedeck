#!/usr/bin/env bash
# assets/AppIcon.icns e dmg-background.tiff vêm dos scripts: o diff do binário precisa vir junto com o script.
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"

fail=0
for s in scripts/make-icon.swift scripts/make-dmg-background.swift; do
  [ -f "$s" ] || { echo "$s: ausente"; fail=1; }
done
grep -q 'AppIcon\.icns\|AppIcon' scripts/make-icon.swift 2>/dev/null || { echo "scripts/make-icon.swift: não gera AppIcon"; fail=1; }
grep -q 'dmg-background' scripts/make-dmg-background.swift 2>/dev/null || { echo "scripts/make-dmg-background.swift: não gera dmg-background"; fail=1; }

if [ -n "${VIBEDECK_FILES:-}" ]; then
  printf '%s\n' "$VIBEDECK_FILES" | grep -q '^assets/' || [ "$fail" -ne 0 ] || exit 77
  has() { printf '%s\n' "$VIBEDECK_FILES" | grep -qx "$1"; }
  if has assets/AppIcon.icns || has assets/AppIcon.png; then
    has scripts/make-icon.swift || { echo "assets/AppIcon.* alterado sem scripts/make-icon.swift no mesmo diff: altere o script e regenere"; fail=1; }
  fi
  if has assets/dmg-background.tiff; then
    has scripts/make-dmg-background.swift || { echo "assets/dmg-background.tiff alterado sem scripts/make-dmg-background.swift no mesmo diff: altere o script e regenere"; fail=1; }
  fi
fi
exit $fail
