# Helpers compartilhados pelos scripts do tópico botao-de-descubra-em-onde-e-regras-nas-revisoes (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
CORE=Sources/VibeDeckCore/ReviewDiscover.swift
APP=Sources/VibeDeckApp/ReviewDiscover.swift
VIEW=Sources/VibeDeckApp/ReviewGroupView.swift
TESTS=Tests/VibeDeckCoreTests/ReviewDiscoverTests.swift
SCOPE='^Sources/VibeDeckCore/ReviewDiscover\.swift$|^Sources/VibeDeckApp/ReviewDiscover[^/]*\.swift$|^Sources/VibeDeckApp/ReviewGroupView\.swift$|^Tests/VibeDeckCoreTests/ReviewDiscoverTests\.swift$'
fail=0

# applies [regex extra]: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa com o escopo (+ extra).
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  local re="$SCOPE"; [ -n "${1:-}" ] && re="$re|$1"
  printf '%s\n' "$VIBEDECK_FILES" | grep -Eq "$re" || exit 77
}

# need <arquivo> <regex ERE> <motivo>: falha se o padrão não aparece no arquivo.
need() {
  grep -qE -- "$2" "$1" || { echo "$1: $3"; fail=1; }
}

# forbid <arquivo> <regex ERE> <motivo>: falha (com linha) se o padrão aparece.
forbid() {
  local hits
  if hits=$(grep -nE -- "$2" "$1"); then
    printf '%s\n' "$hits" | while IFS= read -r h; do echo "$1:${h%%:*}: $3"; done
    fail=1
  fi
}

# body <arquivo> <regex de início>: corpo da declaração (até a chave que fecha no mesmo recuo).
body() {
  RE="$2" awk 'BEGIN { re = ENVIRON["RE"] }
    !f && $0 ~ re { f=1; match($0, /^ */); ind=RLENGTH; print; if ($0 ~ /}[[:space:]]*$/ && $0 !~ /{[[:space:]]*$/) exit; next }
    f { print; match($0, /^ */); if (RLENGTH==ind && $0 ~ /^ *}/) exit }' "$1"
}

# run_tests <Suite/test>...: confere que os @Test existem e roda só eles (Swift Testing).
run_tests() {
  local args=() spec name
  for spec in "$@"; do
    name="${spec##*/}"
    grep -qE "func ${name}\(" "$TESTS" || { echo "$TESTS: teste '${name}' não existe mais (${spec})"; exit 1; }
    args+=(--filter "${spec}")
  done
  swift build --target VibeDeckCoreTests >/dev/null 2>&1 || { swift build --target VibeDeckCoreTests 2>&1 | tail -20; exit 1; }
  local out
  if ! out=$(swift test --skip-build "${args[@]}" 2>&1); then
    printf '%s\n' "$out" | tail -40; exit 1
  fi
  printf '%s\n' "$out" | grep -q "Test run with [1-9][0-9]* test" || { echo "nenhum teste rodou para: $*"; printf '%s\n' "$out" | tail -10; exit 1; }
}

finish() { [ $fail -eq 0 ] || exit 1; }
