# Helpers do tópico colecao-de-artefatos-e-docs-do-claude (use com `source`).
# O domínio vive no Core Rust (crates/); o app SwiftUI só apresenta a coleção.
cd "${VIBEDECK_ROOT:-.}"
CORE=crates/vibedeck-core/src/project/claude.rs
CLI=crates/vibedeck/src/cli/project.rs
MCP=crates/vibedeck/src/mcp/tools/project.rs
MODEL=crates/vibedeck-core/src/model/project.rs
VIEW=Sources/VibeDeckApp/ClaudeItemsView.swift
fail=0

# applies <regex>: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa.
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$1" >/dev/null || exit 77
}
bad() { echo "$1"; fail=1; }
# need <arquivo> <regex ERE> <motivo>
need() { grep -qE -- "$2" "$1" || bad "$1: $3"; }
# forbid <arquivo> <regex ERE> <motivo>
forbid() {
  local hits
  if hits=$(grep -nE -- "$2" "$1"); then
    printf '%s\n' "$hits" | while IFS= read -r h; do echo "$1:${h%%:*}: $3"; done
    fail=1
  fi
}
# fn_body <arquivo> <regex de início>: do início da declaração Rust até a chave de fecho na coluna 0 ou 4.
fn_body() {
  RE="$2" awk 'BEGIN{re=ENVIRON["RE"]} !f && $0 ~ re {f=1; print; next} f {print; if ($0 ~ /^}/) exit}' "$1"
}
for f in "$CORE" "$CLI" "$MCP" "$MODEL" "$VIEW"; do [ -f "$f" ] || { echo "$f: arquivo ausente"; exit 1; }; done
finish() { [ $fail -eq 0 ] || exit 1; exit 0; }
