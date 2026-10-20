#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$CAT" 'public enum KitCatalog' "tipo do catálogo deve estar no Core"
for f in Sources/VibeDeckCore/*.swift; do
  forbid "$f" '^[[:space:]]*(@preconcurrency[[:space:]]+)?import[[:space:]]+(SwiftUI|AppKit|UIKit)\b' "Core não pode importar SwiftUI/AppKit"
done
finish
