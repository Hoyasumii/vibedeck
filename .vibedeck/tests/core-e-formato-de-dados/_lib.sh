# Helpers compartilhados pelos scripts do tópico core-e-formato-de-dados (use com `source`).
cd "${VIBEDECK_ROOT:-.}"

# applies <regex>: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa.
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$1" >/dev/null || exit 77
}

# cargo_tests <pacote> <teste>...: confere que as funções #[test] existem e roda só elas (filtro por nome).
cargo_tests() {
  local pkg="$1" name out; shift
  for name in "$@"; do
    grep -rqE "fn ${name}\(" crates/*/src crates/*/tests || { echo "crates: teste '${name}' não existe mais"; exit 1; }
  done
  if ! out=$(cargo test -p "$pkg" -- "$@" 2>&1); then
    printf '%s\n' "$out" | tail -40; exit 1
  fi
  printf '%s\n' "$out" | grep -E 'test result: ok\. [1-9][0-9]* passed' >/dev/null || { echo "nenhum teste rodou para: $*"; printf '%s\n' "$out" | tail -10; exit 1; }
  printf '%s\n' "$out" | grep -E 'test result: ok\. [1-9][0-9]* passed' | head -3
}
