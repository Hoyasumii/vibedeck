# Helpers compartilhados pelos scripts do tópico visualizador-de-links-para-links (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
F=Sources/VibeDeckApp/LinksView.swift
T=Tests/VibeDeckAppTests/LinkViewerTests.swift
fail=0
bad() { echo "$1"; fail=1; }

# applies <regex>: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa.
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$1" >/dev/null || exit 77
}

[ -f "$F" ] || { echo "$F: arquivo não encontrado"; exit 1; }

# block <regex>: imprime (com número da linha) a 1ª declaração que casa até fechar as chaves.
block() {
  awk -v re="$1" '
    !on && $0 ~ re { on=1; d=0; seen=0 }
    on { print FILENAME ":" FNR ": " $0
         n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); d+=n-m; if (n>0) seen=1
         if (seen && d<=0) exit }' "$F"
}

# need <texto> <regex> <motivo>: falha se o regex não aparece no texto.
need() { grep -Eq -- "$2" <<<"$1" || bad "$F: $3"; }
# deny <texto> <regex> <motivo>: falha (com linha) se o regex aparece no texto.
deny() { local hit; hit=$(grep -E -- "$2" <<<"$1" || true); [ -z "$hit" ] || bad "$3:"$'\n'"$hit"; }

# run_tests <test>...: confere que os @Test existem em LinkViewerTests e roda só eles.
run_tests() {
  local args=() name
  for name in "$@"; do
    grep -qE "func ${name}\(" "$T" || { echo "$T: teste '${name}' não existe mais"; exit 1; }
    args+=(--filter "LinkViewerTests/${name}")
  done
  swift build --build-tests >/dev/null 2>&1 || { swift build --build-tests 2>&1 | tail -20; exit 1; }
  local out
  if ! out=$(swift test --skip-build "${args[@]}" 2>&1); then printf '%s\n' "$out" | tail -40; exit 1; fi
  grep -q "Test run with [1-9][0-9]* test" <<<"$out" || { echo "nenhum teste rodou: $*"; printf '%s\n' "$out" | tail -10; exit 1; }
}
