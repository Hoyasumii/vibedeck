#!/usr/bin/env bash
# Cancelar encerra o pedido sem iniciar nem promover
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
hasF "$SHEET" 'LoggedButton("Cancelar", role: .cancel) { session.ideaRequest = nil }' "Cancelar deve apenas descartar o pedido"
# Escrita no projeto/execução só acontece em finish (após confirmação final)
n=$(grep -c 'prepareIdeaImplementation\|promoteIdea\|implementIdeaRun\|startRun\|session.ask\|resumeWorkflow' "$SHEET" || true)
f=$(block "$SHEET" 'private func finish(')
m=$(grep -c 'prepareIdeaImplementation\|promoteIdea\|implementIdeaRun\|startRun\|session.ask\|resumeWorkflow' <<<"$f" || true)
[ "$n" = "$m" ] || { echo "$WFV: IdeaImplementationSheet inicia/promove fora de finish ($n ocorrências, $m em finish)"; bad=1; }
for fn in 'private func selectWorkflow(' 'private func confirm(restart: Bool)'; do
  notinblock "$SHEET" "$fn" 'prepareIdeaImplementation|promoteIdea|mutateIdea|saveIdea|startRun|session\.ask' "$fn escreve no projeto antes da confirmação"
done
# A sessão não envia nada enquanto o pedido está aberto; stop() também descarta
inblock "$SESSION" 'func send(_ text: String' 'guard !isWorking, ideaRequest == nil else \{ return \}' "send deve ser bloqueado com pedido aberto"
tests 'IdeaEvaluationTests/implementationChoiceAndCancellationHaveNoProjectEffects' implementationChoiceAndCancellationHaveNoProjectEffects
finish
