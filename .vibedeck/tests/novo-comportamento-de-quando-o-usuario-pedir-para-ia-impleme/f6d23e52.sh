#!/usr/bin/env bash
# Pergunta de modo restrita ao app: CLI e MCP sem a nova escolha
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
for f in "$CLI" "$MCP"; do
  none "$f" 'ideaRequest|IdeaRequest|ChatIntent|intentPrompt|intentSchema|requestIdeaImplementation|IdeaImplementationSheet|implementIdeaRun|isEligible' "CLI/MCP não devem usar o fluxo de escolha de modo do app"
done
hasF "$CLI" 'try store.startRun(workflow, input: input, from: from, provider: provider)' "runs start do CLI deve continuar chamando startRun diretamente"
hasF "$MCP" 'try store.startRun(req("workflow"), input: str("input")' "MCP deve continuar chamando startRun diretamente"
# startRun do Core não depende da elegibilidade/modo da ideia
none "$RUNS" 'func startRun[^{]*\{[^}]*isEligible' "startRun não deve exigir elegibilidade"
sr=$(block Sources/VibeDeckCore/ProjectStore.swift 'func startRun(')
[ -z "$sr" ] && sr=$(block "$RUNS" 'func startRun(')
[ -n "$sr" ] || { echo "startRun não encontrado no Core"; bad=1; }
if grep -nE 'IdeaImplementation|ideaRequest|ChatIntent' <<<"$sr"; then echo "startRun do Core passou a depender do modo de implementação"; bad=1; fi
# O modo é app-only: os tipos de sessão/folha ficam no target do app
for f in Sources/VibeDeckCore/*.swift; do
  none "$f" 'IdeaImplementationSheet|ideaRequest' "folha/pedido de modo não pode estar no Core"
done
finish
