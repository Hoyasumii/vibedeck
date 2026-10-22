# Helpers compartilhados pelos scripts do tópico aumentar-o-catalogo-de-padroes (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
T=.vibedeck/tests/aumentar-o-catalogo-de-padroes
CATJSON=crates/vibedeck-core/assets/patterns/catalog.json
PAT=crates/vibedeck-core/src/stack/catalog.rs
TESTS=crates/vibedeck-core/src/stack/catalog.rs
ITESTS=crates/vibedeck-core/tests/stack_patterns.rs
CLIRS=crates/vibedeck/src/cli/stack.rs
MCPRS=crates/vibedeck/src/mcp/tools/stack.rs
APPPAT=Sources/VibeDeckApp/Core/Model/Patterns.swift
VIEW=Sources/VibeDeckApp/PatternsView.swift
BIN=target/debug/vibedeck
SCOPE='^crates/vibedeck-core/assets/patterns/|^crates/vibedeck-core/src/stack/(catalog|patterns)\.rs$|^crates/vibedeck-core/tests/stack_patterns\.rs$|^crates/vibedeck/src/(cli|mcp/tools)/stack\.rs$|^Sources/VibeDeckApp/PatternsView\.swift$|^Sources/VibeDeckApp/Core/Model/Patterns\.swift$|^README\.md$'
NEW_IDS="bdd design-by-contract modular-monolith event-driven value-object domain-service composite proxy"
fail=0

# applies [regex extra]: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa com o escopo (+ extra).
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  local re="$SCOPE"; [ -n "${1:-}" ] && re="$re|$1"
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$re" >/dev/null || exit 77
}

# py <<'PY' … PY: roda python (isolado) lendo o código do stdin, com _catalog importável; as variáveis NEW_IDS/PAT/TESTS/VIEW vão pelo ambiente.
py() { NEW_IDS="$NEW_IDS" PAT="$PAT" TESTS="$TESTS" VIEW="$VIEW" APPPAT="$APPPAT" CATJSON="$CATJSON" python3 -I -c "import sys; sys.path.insert(0, '$T'); exec(sys.stdin.read())"; }

# need <arquivo> <regex ERE> <motivo>
need() { grep -qE -- "$2" "$1" || { echo "$1: $3"; fail=1; }; }

# body <arquivo> <regex de início>: corpo da declaração (até a chave que fecha no mesmo recuo).
body() {
  RE="$2" awk 'BEGIN { re = ENVIRON["RE"] }
    !f && $0 ~ re { f=1; match($0, /^ */); ind=RLENGTH; print; if ($0 ~ /}[[:space:]]*$/ && $0 !~ /{[[:space:]]*$/) exit; next }
    f { print; match($0, /^ */); if (RLENGTH==ind && $0 ~ /^ *}/) exit }' "$1"
}

build_cli() { cargo build -q -p vibedeck --offline 2>/dev/null || { cargo build -p vibedeck --offline 2>&1 | tail -20; exit 1; }; }

# run_tests <arquivo> <função>...: confere que os #[test] existem e roda só eles (cargo test, --lib ou --test conforme o arquivo).
run_tests() {
  local file="$1" spec scope out; shift
  for spec in "$@"; do
    grep -qE "fn ${spec}\(" "$file" || { echo "$file: teste '${spec}' não existe"; exit 1; }
  done
  case "$file" in
    */src/*) scope="-p vibedeck-core --lib" ;;
    */tests/*) scope="-p vibedeck-core --test $(basename "$file" .rs)" ;;
  esac
  if ! out=$(cargo test --offline -q $scope -- "$@" 2>&1); then printf '%s\n' "$out" | tail -40; exit 1; fi
  printf '%s\n' "$out" | grep -E "test result: ok\. [1-9][0-9]* passed" >/dev/null || { echo "nenhum teste rodou para: $*"; printf '%s\n' "$out" | tail -10; exit 1; }
}

finish() { [ $fail -eq 0 ] || exit 1; }
