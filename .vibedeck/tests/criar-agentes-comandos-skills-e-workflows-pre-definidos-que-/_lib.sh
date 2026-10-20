# Helpers do tópico criar-agentes-comandos-skills-e-workflows-pre-definidos-que- (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
CAT=Sources/VibeDeckCore/KitCatalog.swift
INST=Sources/VibeDeckCore/KitInstallation.swift
VIEW=Sources/VibeDeckApp/KitCatalogView.swift
PMODEL=Sources/VibeDeckApp/ProjectModel.swift
CORET=Tests/VibeDeckCoreTests/KitCatalogTests.swift
APPT=Tests/VibeDeckAppTests/KitCatalogAppTests.swift
SCOPE='^Sources/VibeDeckCore/Kit[^/]*\.swift$|^Sources/VibeDeckCore/AIPromptPolicy\.swift$|^Sources/VibeDeckCore/ProjectStore\.swift$|^Sources/VibeDeckApp/KitCatalogView\.swift$|^Sources/VibeDeckApp/ProjectModel\.swift$|^Tests/Vibe[^/]*/KitCatalog[^/]*\.swift$'
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
for f in "$CAT" "$INST" "$VIEW" "$PMODEL" "$CORET" "$APPT"; do [ -f "$f" ] || { echo "$f: arquivo ausente"; exit 1; }; done
finish() { exit "$fail"; }
