# Helpers compartilhados pelos scripts do tópico fluxo-padrao (use com `source`).
cd "${VIBEDECK_ROOT:-.}"
VD_SRC=$(pwd)

# applies <regex>: sai com 77 se VIBEDECK_FILES não está vazio e nenhum arquivo casa.
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -Eq "$1" || exit 77
}

# build_cli: compila o vibedeck do código atual e exporta VD (caminho do binário).
build_cli() {
  local out
  if ! out=$(swift build --product vibedeck 2>&1); then printf '%s\n' "$out" | tail -20; exit 1; fi
  VD="$(swift build --product vibedeck --show-bin-path)/vibedeck"
  [ -x "$VD" ] || { echo "binário do vibedeck não encontrado em $VD"; exit 1; }
}

# new_project: cria um projeto VibeDeck temporário (removido no EXIT) e entra nele. Exporta PROJ.
new_project() {
  PROJ=$(mktemp -d)
  trap 'rm -rf "$PROJ"' EXIT
  cd "$PROJ"
  "$VD" init >/dev/null
}

# mcp <request-json>...: roda `vibedeck mcp` no diretório atual, faz o initialize e envia as requisições
# (cada uma com "id" numérico) por um pipe, uma por vez, esperando cada resposta. Imprime todas as
# respostas, uma por linha (limite 30 s por requisição).
mcp() {
  local out; out=$(mktemp)
  {
    local msg id n
    for msg in '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"vibedeck-rule-test","version":"1"}}}' \
               '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$@"; do
      printf '%s\n' "$msg"
      id=$(printf '%s' "$msg" | sed -nE 's/^\{"jsonrpc":"2.0","id":([0-9]+),.*/\1/p')
      [ -n "$id" ] || continue
      n=0
      while ! grep -q "\"id\":${id}[,}]" "$out"; do
        n=$((n + 1)); [ $n -gt 300 ] && break 2
        sleep 0.1
      done
    done
  } | "$VD" mcp >"$out" 2>/dev/null || true
  local last; last=$(printf '%s' "${@: -1}" | sed -nE 's/^\{"jsonrpc":"2.0","id":([0-9]+),.*/\1/p')
  if ! grep -q "\"id\":${last}[,}]" "$out"; then
    echo "MCP não respondeu à requisição id=$last em 30 s"; cat "$out"; rm -f "$out"; exit 1
  fi
  cat "$out"; rm -f "$out"
}

# call <id> <tool> <arguments-json>: monta um tools/call.
call() { printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2" "$3"; }

# response <id>: filtra da entrada a resposta com esse id.
response() { grep "\"id\":$1[,}]"; }
