#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 133B62CD: o catálogo de kits fica no Core (Rust), sem depender de SwiftUI/AppKit.
need "$KITS" 'pub fn kits\(\)' "catálogo deve ser exposto pelo Core (resources::kits)"
need "$KITS" 'pub fn add_kit_items' "instalação do catálogo deve estar no Core"
need "$KITS" 'include_str!\("\.\./\.\./assets/kits/manutencao\.json"\)' "kit de manutenção deve ser embutido no Core"
forbid "$KITS" 'SwiftUI|AppKit|UIKit' "o catálogo do Core não pode depender de UI"
if grep -rliE 'swiftui|appkit|uikit' crates/vibedeck-core/Cargo.toml crates/vibedeck-core/src >/dev/null; then
  grep -rliE 'swiftui|appkit|uikit' crates/vibedeck-core/Cargo.toml crates/vibedeck-core/src | sed 's/$/: o Core não pode depender de UI/'; fail=1
fi
# O app usa o catálogo por MCP.
need "$PMODEL" 'store\.call\("add_kit"' "o app deve adicionar via MCP add_kit"
finish
