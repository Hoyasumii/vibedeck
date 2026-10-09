#!/usr/bin/env bash
# O fluxo rules_for → verificar → submit_rule_check (pass/fail/na) → passed=false? corrigir e reenviar
# continua comunicado pelo AGENTS.md gerado, pelas instruções do MCP e pelo CLI.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/vibedeck/|^Sources/VibeDeckCore/(AgentsGuide|ProjectStore)\.swift$'
build_cli
new_project
fail=0

# steps <origem> <texto>: os quatro passos aparecem, na ordem.
steps() {
  local src=$1 text=$2 prev=0 n label pat
  for pair in "rules_for|rules_for" "verificar|[Vv]erifique" "submit_rule_check|submit_rule_check" "pass/fail/na|pass.{1,6}fail.{1,6}na" "passed=false → reenviar|passed[^a-z]{0,4}(=|for)[^a-z]{0,4}false"; do
    label=${pair%%|*}; pat=${pair#*|}
    n=$(printf '%s\n' "$text" | grep -nE "$pat" | head -1 | cut -d: -f1 || true)
    if [ -z "$n" ]; then echo "$src: não descreve o passo '$label'"; fail=1; continue; fi
    [ "$n" -ge "$prev" ] || { echo "$src: passo '$label' (linha $n) fora de ordem"; fail=1; }
    prev=$n
  done
  printf '%s\n' "$text" | grep -qiE 'corrija e envie' || { echo "$src: não manda corrigir e reenviar o check quando passed=false"; fail=1; }
}

# AGENTS.md gerado pelo código atual (seção de regras, até a próxima seção ##).
guide=$(awk '/^## .*Regras/{f=1;next} f&&/^## /{exit} f' .vibedeck/AGENTS.md)
[ -n "$guide" ] || { echo "Sources/VibeDeckCore/AgentsGuide.swift: AGENTS.md gerado não tem a seção de regras"; fail=1; }
steps "Sources/VibeDeckCore/AgentsGuide.swift (AGENTS.md)" "$guide"

# Instruções do MCP, como o servidor as entrega no initialize.
init=$(mcp '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
instr=$(printf '%s\n' "$init" | response 0 | sed -E 's/.*"instructions":"(([^"\\]|\\.)*)".*/\1/' | sed 's/\\n/\n/g; s/\\"/"/g')
steps "Sources/vibedeck/MCPServer.swift (instruções do MCP)" "$instr"
tools=$(printf '%s\n' "$init" | response 1)
for t in rules_for submit_rule_check; do
  printf '%s' "$tools" | grep -q "\"name\":\"$t\"" || { echo "Sources/vibedeck/MCPServer.swift: ferramenta $t sumiu do MCP"; fail=1; }
done

# CLI: `rules for` e `rules check` existem e o check pede pass/fail/na.
"$VD" help rules for >/dev/null 2>&1 || { echo "Sources/vibedeck/CLI.swift: 'vibedeck rules for' sumiu"; fail=1; }
"$VD" help rules check 2>/dev/null | grep -qE 'pass.{1,3}fail.{1,3}na' || { echo "Sources/vibedeck/CLI.swift: 'vibedeck rules check' sumiu ou não explica pass/fail/na"; fail=1; }

exit $fail
