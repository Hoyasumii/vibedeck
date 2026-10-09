#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
# Não se aplica quando a tarefa não tocou em Sources/VibeDeckApp.
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -qE "^Sources/VibeDeckApp/|^Package\.swift$"; then exit 77; fi
fail=0
bad() { echo "$1: $2"; fail=1; }
# Sem assets de ícone próprios, sem SwiftUI.Link, dependências de UI só MarkdownUI e SwiftTerm (1.11.x).
for a in $(find Sources/VibeDeckApp Sources/vibedeck -name '*.xcassets' -o -name '*.png' -o -name '*.svg' -o -name '*.pdf' -o -name '*.icns' 2>/dev/null); do
  bad "$a" "asset de imagem próprio (use SF Symbols)"
done
while IFS=: read -r f n line; do
  [[ "${line%%//*}" =~ Image\(\" ]] && bad "$f:$n" "Image(\"nome\") de asset (use Image(systemName:)): ${line#"${line%%[![:space:]]*}"}"
done < <(grep -nE 'Image\("' Sources/VibeDeckApp/*.swift | sed -E 's/^([^:]+):([0-9]+):/\1:\2:/' || true)
while IFS=: read -r f n line; do
  [[ "${line%%//*}" =~ (^|[^A-Za-z.])Link\(destination || "${line%%//*}" == *SwiftUI.Link* ]] && bad "$f:$n" "SwiftUI.Link (use o Link do Core via Aliases.swift/ProjectLink)"
done < <(grep -nE 'Link\(destination|SwiftUI\.Link' Sources/VibeDeckApp/*.swift || true)
allowed='swift-argument-parser|swift-sdk|swift-markdown-ui|SwiftTerm'
while IFS= read -r url; do
  echo "$url" | grep -qE "/($allowed)(\.git)?\"" || bad Package.swift "dependência nova: $url (UI só MarkdownUI e SwiftTerm)"
done < <(grep -oE '\.package\(url: "[^"]+"' Package.swift || true)
grep -qE 'SwiftTerm\.git", \.upToNextMinor\(from: "1\.11\.0"\)' Package.swift || bad Package.swift "SwiftTerm deve ficar fixado em .upToNextMinor(from: \"1.11.0\")"
exit $fail
