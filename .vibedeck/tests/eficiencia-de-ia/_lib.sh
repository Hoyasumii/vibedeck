# Helpers compartilhados pelos scripts do tópico eficiencia-de-ia (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
POLICY=crates/vibedeck-core/src/ai/policy_instructions.txt
APP_POLICY=Sources/VibeDeckApp/Core/AI/AIPromptPolicy.swift

# cargo_test <args de cargo test, incluindo filtros>: falha com o final da saída se algum teste falhar ou nenhum rodar.
cargo_test() {
  local out
  if ! out=$(cargo test -q "$@" 2>&1); then printf '%s\n' "$out" | tail -40; exit 1; fi
  printf '%s\n' "$out" | grep -q "test result: ok. [1-9]" || { echo "nenhum teste rodou para: $*"; printf '%s\n' "$out" | tail -10; exit 1; }
}
