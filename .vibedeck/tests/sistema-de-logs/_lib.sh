# Helpers compartilhados pelos scripts do tópico sistema-de-logs (use com `source`).
cd "${VIBEDECK_ROOT:-.}"

# applies <regex>: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa.
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$1" >/dev/null || exit 77
}

# Registro de logs: o Core Rust (leitura/armazém) e o app (escrita das ações, port em Swift do mesmo formato).
RUSTLOG=crates/vibedeck-core/src/project/logs.rs
APPLOG=Sources/VibeDeckApp/Core/Support/Logging.swift
LOG_SCOPE='^crates/vibedeck-core/src/project/logs\.rs$|^Sources/VibeDeckApp/|^crates/vibedeck/src/(cli|mcp)/|^README\.md$|^\.vibedeck/guide\.md$'

# run_tests <teste>...: confere que os #[test] do módulo de logs existem e roda só eles (cargo test, Core Rust).
run_tests() {
  local name filters=()
  for name in "$@"; do
    grep -qE "fn ${name}\(" "$RUSTLOG" || { echo "$RUSTLOG: teste '${name}' não existe mais"; exit 1; }
    filters+=("project::logs::tests::${name}")
  done
  local out
  if ! out=$(cargo test -q -p vibedeck-core --lib -- "${filters[@]}" 2>&1); then
    printf '%s\n' "$out" | tail -40; exit 1
  fi
  printf '%s\n' "$out" | grep -q "test result: ok. [1-9]" || { echo "nenhum teste rodou para: $*"; printf '%s\n' "$out" | tail -10; exit 1; }
}

# region <arquivo> <regex-inicio> <regex-fim>: imprime o trecho (inclusive) do início até o próximo fim.
region() { awk -v s="$2" -v e="$3" '$0 ~ s {on=1} on {print} on && NR>1 && $0 ~ e && $0 !~ s {exit}' "$1"; }
