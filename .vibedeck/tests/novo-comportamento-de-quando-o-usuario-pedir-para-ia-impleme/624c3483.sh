#!/usr/bin/env bash
# Execução existente para a ideia+workflow pergunta Retomar ou Reiniciar
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
s=$(block "$SHEET" 'private func selectWorkflow(')
grep -q 'existing = model.ideaRun(idea, workflow: slug)?.value' <<<"$s" || { echo "$WFV: selectWorkflow não procura execução anterior da ideia"; bad=1; }
grep -q 'if existing == nil { confirm(restart: false) }' <<<"$s" || { echo "$WFV: selectWorkflow continua mesmo com execução anterior"; bad=1; }
e=$(block "$SHEET" '} else if let existing {')
grep -q 'LoggedButton("Retomar") { confirm(restart: false) }' <<<"$e" || { echo "$WFV: opção Retomar ausente"; bad=1; }
grep -q 'LoggedButton("Reiniciar") { confirm(restart: true) }' <<<"$e" || { echo "$WFV: opção Reiniciar ausente"; bad=1; }
# Workflow explícito do chat passa pelo mesmo caminho
t=$(block "$SHEET" '.task {')
grep -q 'selectWorkflow(workflow)' <<<"$t" || { echo "$WFV: workflow explícito do chat não passa por selectWorkflow"; bad=1; }
# Execução surgida após a pergunta volta a perguntar
f=$(block "$SHEET" 'private func finish(')
grep -q 'latest.id != existing?.id' <<<"$f" || { echo "$WFV: finish não revalida execução existente"; bad=1; }
finish
