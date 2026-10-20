#!/usr/bin/env bash
# decisão do status fica no Core e o app a usa
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
grep -q 'idea.status = .approved' Sources/VibeDeckCore/RuleDiscover.swift || { echo "Sources/VibeDeckCore/RuleDiscover.swift: lógica de aprovação ausente"; exit 1; }
if grep -q 'import SwiftUI' Sources/VibeDeckCore/RuleDiscover.swift; then echo "Core RuleDiscover.swift importa SwiftUI"; exit 1; fi
grep -q 'verdict.apply(to:' Sources/VibeDeckApp/IdeaView.swift || { echo "IdeaView.swift não usa verdict.apply(to:)"; exit 1; }
if grep -n 'status = \.approved' Sources/VibeDeckApp/*.swift; then echo "App decide status approved por conta própria"; exit 1; fi
