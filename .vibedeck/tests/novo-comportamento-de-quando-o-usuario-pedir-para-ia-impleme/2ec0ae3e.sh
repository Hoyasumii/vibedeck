#!/usr/bin/env bash
# Pedido explícito de execução padrão segue sem repetir a pergunta
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
t=$(block "$SHEET" '.task {')
grep -q 'if request.mode == .standard { confirm(restart: false) }' <<<"$t" || { echo "$WFV: modo standard explícito deve confirmar direto em .task"; bad=1; }
grep -q 'VDLog.$actionID.withValue(request.actionID)' <<<"$t" || { echo "$WFV: .task deve rodar sob o actionID do pedido"; bad=1; }
# confirm leva direto a finish (sem voltar ao seletor) quando não há globs órfãos
c=$(block "$SHEET" 'private func confirm(restart: Bool)')
grep -q 'if stalePaths.isEmpty { finish() }' <<<"$c" || { echo "$WFV: confirm não segue para finish"; bad=1; }
if grep -q 'choosingWorkflow' <<<"$c"; then echo "$WFV: confirm reabre seletor de workflow"; bad=1; fi
# Sem workflow escolhido, finish envia o prompt padrão
f=$(block "$SHEET" 'private func finish(')
grep -q 'session.ask(prepared.prompt, inspectIdeas: false)' <<<"$f" || { echo "$WFV: finish não envia o prompt padrão sem reclassificar"; bad=1; }
hasF "$RULES" 'standard quando pediu execução padrão/sem workflow' "intentPrompt não mapeia execução padrão explícita para standard"
hasF "$SESSION" 'ideaRequest = IdeaRequest(ideaID: idea.id, mode: intent.mode, workflow: intent.workflow)' "modo do chat não é repassado à folha"
finish
