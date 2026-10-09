#!/usr/bin/env bash
# O add_idea continua no MCP (registra author=ai, status new), as instruções do MCP o mencionam e o ciclo
# new → exploring → approved → promote_idea continua possível.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/vibedeck/|^Sources/VibeDeckCore/(Models|ProjectStore)\.swift$'
build_cli
new_project
fail=0
M=Sources/vibedeck/MCPServer.swift

c2=$(call 2 add_idea '{"title":"Ideia de teste","body":"surgiu durante o trabalho"}')
c3=$(call 3 update_idea '{"idea":"ideia-de-teste","status":"exploring"}')
c4=$(call 4 update_idea '{"idea":"ideia-de-teste","status":"approved"}')
out=$(mcp '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "$c2" "$c3" "$c4")

instr=$(printf '%s\n' "$out" | response 0)
printf '%s' "$instr" | grep -q 'add_idea' || { echo "$M: instruções do MCP não mencionam add_idea"; fail=1; }
tools=$(printf '%s\n' "$out" | response 1)
for t in add_idea update_idea promote_idea; do
  printf '%s' "$tools" | grep -q "\"name\":\"$t\"" || { echo "$M: ferramenta $t sumiu do MCP"; fail=1; }
done

r2=$(printf '%s\n' "$out" | response 2)
if printf '%s' "$r2" | grep -q '"isError":true'; then
  echo "$M: add_idea falhou: $r2"; fail=1
else
  file=$(ls .vibedeck/ideas/*.json 2>/dev/null | head -1)
  if [ -z "$file" ]; then echo "$M: add_idea não gravou a ideia em .vibedeck/ideas/"; fail=1
  else
    grep -qE '"author" *: *"ai"' "$file" || { echo "$M: add_idea não marca author=ai"; fail=1; }
  fi
  printf '%s' "$r2" | grep -qE 'status[^a-z]+:[^a-z]+new' || { echo "$M: ideia nova não começa com status new: $r2"; fail=1; }
fi
for id in 3 4; do
  printf '%s\n' "$out" | response $id | grep -q '"isError":true' && { echo "$M: update_idea não aceitou a etapa do ciclo (requisição $id)"; fail=1; }
done
file=$(ls .vibedeck/ideas/*.json 2>/dev/null | head -1)
[ -n "$file" ] && ! grep -qE '"status" *: *"approved"' "$file" && { echo "$M: a ideia não chegou a approved pelo update_idea"; fail=1; }

exit $fail
