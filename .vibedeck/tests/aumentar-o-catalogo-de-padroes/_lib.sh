# Helpers compartilhados pelos scripts do tópico aumentar-o-catalogo-de-padroes (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
T=.vibedeck/tests/aumentar-o-catalogo-de-padroes
PAT=Sources/VibeDeckCore/Patterns.swift
TESTS=Tests/VibeDeckCoreTests/PatternsTests.swift
VIEW=Sources/VibeDeckApp/PatternsView.swift
SCOPE='^Sources/VibeDeckCore/Patterns\.swift$|^Tests/VibeDeckCoreTests/PatternsTests\.swift$|^Sources/VibeDeckApp/PatternsView\.swift$|^Sources/vibedeck/(CLI|MCPServer)\.swift$|^README\.md$'
NEW_IDS="bdd design-by-contract modular-monolith event-driven value-object domain-service composite proxy"
fail=0

# applies [regex extra]: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa com o escopo (+ extra).
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  local re="$SCOPE"; [ -n "${1:-}" ] && re="$re|$1"
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$re" >/dev/null || exit 77
}

# py <<'PY' … PY: roda python (isolado) lendo o código do stdin, com _catalog importável; as variáveis NEW_IDS/PAT/TESTS/VIEW vão pelo ambiente.
py() { NEW_IDS="$NEW_IDS" PAT="$PAT" TESTS="$TESTS" VIEW="$VIEW" python3 -I -c "import sys; sys.path.insert(0, '$T'); exec(sys.stdin.read())"; }

# need <arquivo> <regex ERE> <motivo>
need() { grep -qE -- "$2" "$1" || { echo "$1: $3"; fail=1; }; }

# body <arquivo> <regex de início>: corpo da declaração (até a chave que fecha no mesmo recuo).
body() {
  RE="$2" awk 'BEGIN { re = ENVIRON["RE"] }
    !f && $0 ~ re { f=1; match($0, /^ */); ind=RLENGTH; print; if ($0 ~ /}[[:space:]]*$/ && $0 !~ /{[[:space:]]*$/) exit; next }
    f { print; match($0, /^ */); if (RLENGTH==ind && $0 ~ /^ *}/) exit }' "$1"
}

build_cli() { swift build --product vibedeck >/dev/null 2>&1 || { swift build --product vibedeck 2>&1 | tail -20; exit 1; }; }

# run_tests <Suite/test>...: confere que os @Test existem e roda só eles (Swift Testing).
run_tests() {
  local args=() spec name
  for spec in "$@"; do
    name="${spec##*/}"
    grep -qE "func ${name}\(" "$TESTS" || { echo "$TESTS: teste '${name}' não existe (${spec})"; exit 1; }
    args+=(--filter "${spec}")
  done
  swift build --build-tests >/dev/null 2>&1 || { swift build --build-tests 2>&1 | tail -20; exit 1; }
  local out
  if ! out=$(swift test --skip-build "${args[@]}" 2>&1); then printf '%s\n' "$out" | tail -40; exit 1; fi
  printf '%s\n' "$out" | grep "Test run with [1-9][0-9]* test" >/dev/null || { echo "nenhum teste rodou para: $*"; printf '%s\n' "$out" | tail -10; exit 1; }
}

finish() { [ $fail -eq 0 ] || exit 1; }
