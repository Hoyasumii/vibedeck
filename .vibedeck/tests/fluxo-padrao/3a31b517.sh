#!/usr/bin/env bash
# Item com regras (campo rules ou target.file casando um tópico) vai a in_progress livremente, mas done é
# bloqueado sem check aprovado, com mensagem em pt-BR, no CLI e no MCP; --force (CLI) e um check aprovado liberam.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/vibedeck/|^Sources/VibeDeckCore/(Models|ProjectStore|Rules|RuleTests)\.swift$'
build_cli
new_project
fail=0
MSG='não pode ser concluído sem passar pelas regras'

"$VD" rules new UI --path 'Sources/App/**' >/dev/null
rule=$("$VD" rules add UI "Sem minWidth" | cut -f1)
by_rules=$("$VD" review add G "Por campo rules" --kind fix --rules ui | cut -f1)
by_target=$("$VD" review add G "Por alvo" --kind fix --file Sources/App/Side.swift | cut -f1)
free=$("$VD" review add G "Sem regras" --kind fix --file README.md | cut -f1)

# in_progress nunca é bloqueado.
"$VD" review set "$by_rules" --status in_progress >/dev/null || { echo "Sources/vibedeck/CLI.swift: marcar in_progress falhou"; fail=1; }

# done sem check: falha com mensagem em pt-BR (pelo campo rules e pelo target.file).
for id in "$by_rules" "$by_target"; do
  if out=$("$VD" review set "$id" --status done 2>&1); then
    echo "Sources/vibedeck/CLI.swift: review set --status done passou sem check aprovado (item $id)"; fail=1
  else
    printf '%s' "$out" | grep -q "$MSG" || { echo "Sources/VibeDeckCore/ProjectStore.swift: mensagem do bloqueio não está em pt-BR: $out"; fail=1; }
  fi
done
"$VD" review list --status done --json | grep -q "$by_rules" &&{ echo "Sources/vibedeck/CLI.swift: item bloqueado ficou done mesmo assim"; fail=1; }

# Item sem regras conclui direto.
"$VD" review set "$free" --status done >/dev/null 2>&1 || { echo "Sources/vibedeck/CLI.swift: item sem regras foi bloqueado"; fail=1; }

# MCP: mesmo bloqueio, mesma mensagem.
# (argumentos montados fora do "$(...)": o bash 3.2 do macOS perde as aspas aninhadas ali.)
a1=$(printf '{"id":"%s","status":"done"}' "$by_target")
a2=$(printf '{"id":"%s","status":"in_progress"}' "$by_rules")
c1=$(call 1 update_review_item "$a1"); c2=$(call 2 update_review_item "$a2")
out=$(mcp "$c1" "$c2")
r1=$(printf '%s\n' "$out" | response 1)
printf '%s' "$r1" | grep -q '"isError":true' || { echo "Sources/vibedeck/MCPServer.swift: update_review_item status=done passou sem check aprovado"; fail=1; }
printf '%s' "$r1" | grep -q "$MSG" || { echo "Sources/vibedeck/MCPServer.swift: bloqueio do done sem mensagem em pt-BR: $r1"; fail=1; }
printf '%s\n' "$out" | response 2 | grep -q '"isError":true' && { echo "Sources/vibedeck/MCPServer.swift: update_review_item status=in_progress falhou"; fail=1; }

# Check só de scripts deixa a regra manual 'must' pendente: ainda bloqueia.
"$VD" rules check --task t --item "$by_rules" >/dev/null 2>&1 || true
"$VD" review set "$by_rules" --status done >/dev/null 2>&1 && { echo "Sources/VibeDeckCore/ProjectStore.swift: check sem as regras manuais 'must' liberou o done"; fail=1; }

# Check reprovado ainda bloqueia; aprovado (com as manuais verificadas) libera.
printf '[{"ruleId":"%s","verdict":"fail","note":"x"}]' "$rule" | "$VD" rules check --manual --task t --item "$by_rules" >/dev/null 2>&1 || true
"$VD" review set "$by_rules" --status done >/dev/null 2>&1 && { echo "Sources/VibeDeckCore/ProjectStore.swift: check reprovado liberou o done"; fail=1; }
printf '[{"ruleId":"%s","verdict":"pass","note":"ok"}]' "$rule" | "$VD" rules check --manual --task t --item "$by_rules" >/dev/null 2>&1 || true
"$VD" review set "$by_rules" --status done >/dev/null 2>&1 || { echo "Sources/VibeDeckCore/ProjectStore.swift: check aprovado não liberou o done"; fail=1; }

# Humano força com --force.
"$VD" review set "$by_target" --status done --force >/dev/null 2>&1 || { echo "Sources/vibedeck/CLI.swift: --force não conclui o item"; fail=1; }

exit $fail
