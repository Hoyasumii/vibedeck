#!/usr/bin/env bash
# Implementar em ideia elegível abre Workflow / Execução padrão / Cancelar antes de iniciar
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# No IdeaView, o ramo elegível só registra o pedido (sem promover nem enviar prompt)
elig=$(segment "$IDEAV" 'if IdeaImplementation.isEligible(current) {' '} else if')
[ -n "$elig" ] || { echo "$IDEAV: ramo elegível de Implementar não encontrado"; bad=1; }
grep -q 'session.requestIdeaImplementation(current)' <<<"$elig" || { echo "$IDEAV: ramo elegível não chama session.requestIdeaImplementation"; bad=1; }
if grep -nE 'promoteIdea|implement\(|session\.ask|prepareIdeaImplementation' <<<"$elig"; then echo "$IDEAV: ramo elegível inicia/promove antes da escolha"; bad=1; fi
# A sessão só guarda o pedido; a janela apresenta a folha
inblock "$SESSION" 'func requestIdeaImplementation' 'ideaRequest = IdeaRequest\(ideaID: idea.id\)' "pedido não é registrado em ideaRequest"
notinblock "$SESSION" 'func requestIdeaImplementation' 'send\(|ask\(|startRun|promote' "requestIdeaImplementation inicia algo antes da escolha"
has "$WINDOW" 'sheet\(item: Binding\(get: \{ claude\.ideaRequest \}' "ideaRequest não abre a folha"
has "$WINDOW" 'IdeaImplementationSheet\(request: request\)' "folha IdeaImplementationSheet não apresentada"
# Folha: modo padrão (.ask) não confirma sozinho; oferece Workflow (com workflows), Execução padrão e Cancelar
hasF "$SHEET" 'if !model.workflows.isEmpty {' "botão Workflow deve aparecer quando há workflows"
hasF "$SHEET" 'LoggedButton("Workflow") { choosingWorkflow = true }' "botão Workflow ausente"
hasF "$SHEET" 'LoggedButton("Execução padrão")' "botão Execução padrão ausente"
hasF "$SHEET" 'LoggedButton("Cancelar", role: .cancel)' "botão Cancelar ausente"
hasF "$SESSION" 'var mode: IdeaImplementation.ChatIntent.Mode = .ask' "pedido do botão deve ter modo .ask por padrão"
t=$(block "$SHEET" '.task {')
if grep -qE 'request.mode == .ask' <<<"$t"; then echo "$WFV: .task não deve agir no modo .ask"; bad=1; fi
tests 'IdeaEvaluationTests/implementationChoiceAndCancellationHaveNoProjectEffects' implementationChoiceAndCancellationHaveNoProjectEffects
finish
