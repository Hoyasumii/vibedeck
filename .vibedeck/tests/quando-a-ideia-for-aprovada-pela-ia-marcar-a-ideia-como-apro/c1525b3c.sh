#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# C1525B3C: a lógica que decide o status a partir do veredito fica no código de domínio (sem SwiftUI) e é usada pelo app.
grep -q 'idea.status = .approved' "$LOGIC" || bad "$LOGIC: lógica de aprovação ausente"
grep -qE '^import (SwiftUI|AppKit)' "$LOGIC" && bad "$LOGIC importa SwiftUI/AppKit"
grep -q 'verdict.apply(to:' "$IDEAV" || bad "$IDEAV não usa verdict.apply(to:)"
if grep -n 'status = \.approved' Sources/VibeDeckApp/*.swift; then bad "O app decide status approved por conta própria"; fi
finish
