# Helpers compartilhados pelos scripts do tópico botao-de-descubra-em-onde-e-regras-nas-revisoes (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
# O Descubra de revisões vive no código de domínio do app (ReviewDiscoverLogic.swift, usado pela UI) e tem um
# gêmeo no Core Rust (crates/vibedeck-core/src/reviews/discover.rs, com testes); os scripts conferem os dois.
CORE=Sources/VibeDeckApp/Core/Discover/ReviewDiscoverLogic.swift
APP=Sources/VibeDeckApp/ReviewDiscover.swift
VIEW=Sources/VibeDeckApp/ReviewGroupView.swift
RS=crates/vibedeck-core/src/reviews/discover.rs
OPERATION=Sources/VibeDeckApp/AIReadOnlyOperation.swift
SCOPE='^Sources/VibeDeckApp/Core/Discover/ReviewDiscoverLogic\.swift$|^Sources/VibeDeckApp/ReviewDiscover[^/]*\.swift$|^Sources/VibeDeckApp/ReviewGroupView\.swift$|^Sources/VibeDeckApp/AIReadOnlyOperation\.swift$|^crates/vibedeck-core/src/reviews/discover\.rs$'
fail=0

# applies [regex extra]: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa com o escopo (+ extra).
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  local re="$SCOPE"; [ -n "${1:-}" ] && re="$re|$1"
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$re" >/dev/null || exit 77
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

# rtest <nome>...: confere que os testes Rust do Descubra existem em discover.rs (rodam em `cargo test -p vibedeck-core reviews::discover`).
rtest() {
  local n
  for n in "$@"; do grep -qE "fn ${n}\(" "$RS" || { echo "$RS: teste '${n}' não existe"; fail=1; }; done
}

# Código do Core Rust sem o módulo de testes (os testes citam de propósito o que é proibido no código).
RSC=$(mktemp); trap 'rm -f "$RSC"' EXIT
[ -f "$RS" ] && awk '/^#\[cfg\(test\)\]/{exit} {print}' "$RS" > "$RSC"
# forbid_rs <regex ERE> <motivo>: como forbid, mas só no código (não nos testes) de discover.rs.
forbid_rs() {
  local hits
  if hits=$(grep -nE -- "$1" "$RSC"); then
    printf '%s\n' "$hits" | while IFS= read -r h; do echo "$RS:${h%%:*}: $2"; done
    fail=1
  fi
}

finish() { [ $fail -eq 0 ] || exit 1; }
