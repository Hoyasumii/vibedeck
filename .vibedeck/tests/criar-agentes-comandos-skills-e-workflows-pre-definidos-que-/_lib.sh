# Helpers do tópico criar-agentes-comandos-skills-e-workflows-pre-definidos-que- (use com `source`).
# O catálogo e a instalação vivem no Core Rust (crates/vibedeck-core); o app só seleciona e chama o MCP (`add_kit`).
cd "${VIBEDECK_ROOT:-.}"
KITS=crates/vibedeck-core/src/resources/kits.rs
PERSONA=crates/vibedeck-core/src/resources/persona.rs
ASSETS=crates/vibedeck-core/assets/kits
CORET=crates/vibedeck-core/tests/resources_core.rs
VIEW=Sources/VibeDeckApp/KitCatalogView.swift
PMODEL=Sources/VibeDeckApp/ProjectModel.swift
SCOPE='^crates/vibedeck-core/src/resources/(kits|persona)\.rs$|^crates/vibedeck-core/assets/kits/|^crates/vibedeck-core/tests/resources_core\.rs$|^crates/vibedeck/src/(cli|mcp/tools)/resources\.rs$|^Sources/VibeDeckApp/(KitCatalogView|ProjectModel)\.swift$|^Sources/VibeDeckApp/Core/Model/Kit[^/]*\.swift$'
fail=0
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$SCOPE" >/dev/null || exit 77
}
need() { grep -qE -- "$2" "$1" || { echo "$1: $3"; fail=1; }; }
forbid() {
  local hits
  if hits=$(grep -nE -- "$2" "$1"); then
    printf '%s\n' "$hits" | while IFS= read -r h; do echo "$1:${h%%:*}: $3"; done
    fail=1
  fi
}
for f in "$KITS" "$PERSONA" "$VIEW" "$PMODEL" "$ASSETS/manutencao.json" "$ASSETS/novas-ferramentas.json" "$ASSETS/guidance.txt" crates/vibedeck-core/src/ai/policy_instructions.txt; do [ -f "$f" ] || { echo "$f: arquivo ausente"; exit 1; }; done
finish() { exit "$fail"; }
