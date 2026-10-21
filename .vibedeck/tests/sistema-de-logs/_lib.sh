# Helpers compartilhados pelos scripts do tópico sistema-de-logs (use com `source`).
cd "${VIBEDECK_ROOT:-.}"

# applies <regex>: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa.
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$1" >/dev/null || exit 77
}

LOG_SCOPE='^Sources/VibeDeckCore/Logging\.swift$|^Sources/VibeDeckApp/|^Tests/VibeDeckCoreTests/LoggingTests\.swift$|^Sources/vibedeck/(CLI|MCPServer)\.swift$|^README\.md$|^\.vibedeck/guide\.md$'

# run_tests <Suite/test>...: confere que os @Test existem e roda só eles (Swift Testing).
run_tests() {
  local args=() spec name
  for spec in "$@"; do
    name="${spec##*/}"
    if [ "$name" = "$spec" ]; then
      grep -rqE "struct ${name}\b" Tests/VibeDeckCoreTests || { echo "Tests/VibeDeckCoreTests: suíte '${name}' não existe mais"; exit 1; }
    else
      grep -rqE "func ${name}\(" Tests/VibeDeckCoreTests || { echo "Tests/VibeDeckCoreTests: teste '${name}' não existe mais (${spec})"; exit 1; }
    fi
    args+=(--filter "${spec}")
  done
  swift build --build-tests >/dev/null 2>&1 || { swift build --build-tests 2>&1 | tail -20; exit 1; }
  local out
  if ! out=$(swift test --skip-build "${args[@]}" 2>&1); then
    printf '%s\n' "$out" | tail -40; exit 1
  fi
  printf '%s\n' "$out" | grep  "Test run with [1-9][0-9]* test" >/dev/null || { echo "nenhum teste rodou para: $*"; printf '%s\n' "$out" | tail -10; exit 1; }
}

# region <arquivo> <regex-inicio> <regex-fim>: imprime o trecho (inclusive) do início até o próximo fim.
region() { awk -v s="$2" -v e="$3" '$0 ~ s {on=1} on {print} on && NR>1 && $0 ~ e && $0 !~ s {exit}' "$1"; }
