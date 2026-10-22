#!/usr/bin/env bash
# Opção Workflow permite selecionar um workflow existente
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
cw=$(block "$SHEET" '} else if choosingWorkflow {')
grep -q 'ForEach(model.workflows) { entry in' <<<"$cw" || { echo "$WFV: seletor não lista model.workflows"; bad=1; }
grep -q 'selectWorkflow(entry.slug)' <<<"$cw" || { echo "$WFV: item do seletor não seleciona o workflow"; bad=1; }
grep -q 'entry.value.title' <<<"$cw" || { echo "$WFV: item do seletor não mostra o título do workflow"; bad=1; }
hasF "$SHEET" 'LoggedButton("Workflow") { choosingWorkflow = true }' "botão Workflow não abre o seletor"
f=$(block "$SHEET" 'private func finish(')
grep -q 'prepareIdeaImplementation(request.ideaID, workflow: workflow' <<<"$f" || { echo "$WFV: workflow escolhido não é usado na implementação"; bad=1; }
grep -q 'session.resumeWorkflow(execution.ref, run: execution.run, store: model.store)' <<<"$f" || { echo "$WFV: execução do workflow escolhido não é iniciada"; bad=1; }
finish
