# Helpers compartilhados pelos scripts do tópico core-e-formato-de-dados (use com `source`).
cd "${VIBEDECK_ROOT:-.}"

# applies <regex>: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa.
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -Eq "$1" || exit 77
}

# run_tests <Suite/test>...: confere que os @Test existem e roda só eles (Swift Testing).
run_tests() {
  local args=() spec suite name
  for spec in "$@"; do
    suite="${spec%%/*}"; name="${spec##*/}"
    grep -rqE "func ${name}\(" Tests/VibeDeckCoreTests || { echo "Tests/VibeDeckCoreTests: teste '${name}' não existe mais (${spec})"; exit 1; }
    args+=(--filter "${suite}/${name}")
  done
  swift build --target VibeDeckCoreTests >/dev/null 2>&1 || { swift build --target VibeDeckCoreTests 2>&1 | tail -20; exit 1; }
  local out
  if ! out=$(swift test --skip-build "${args[@]}" 2>&1); then
    printf '%s\n' "$out" | tail -40; exit 1
  fi
  printf '%s\n' "$out" | grep -q "Test run with [1-9][0-9]* test" || { echo "nenhum teste rodou para: $*"; printf '%s\n' "$out" | tail -10; exit 1; }
  printf '%s\n' "$out" | tail -3
}
