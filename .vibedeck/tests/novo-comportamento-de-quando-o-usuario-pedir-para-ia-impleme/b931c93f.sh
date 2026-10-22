#!/usr/bin/env bash
# Pedido explícito com workflow existente seleciona o workflow sem a pergunta de modo
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
t=$(block "$SHEET" '.task {')
grep -q 'if let workflow = request.workflow { selectWorkflow(workflow) }' <<<"$t" || { echo "$WFV: workflow explícito não é selecionado em .task"; bad=1; }
grep -q 'else if request.mode == .workflow {' <<<"$t" || { echo "$WFV: .task não trata modo workflow"; bad=1; }
s=$(block "$SHEET" 'private func selectWorkflow(')
grep -q 'workflow = slug' <<<"$s" || { echo "$WFV: selectWorkflow não guarda o workflow"; bad=1; }
grep -q 'if existing == nil { confirm(restart: false) }' <<<"$s" || { echo "$WFV: selectWorkflow não segue direto quando não há execução anterior"; bad=1; }
# Só workflows existentes são aceitos da classificação
inblock "$SESSION" 'private func inspectIdeaRequest' 'intent.workflow == nil \|\| workflows.contains\(where: \{ \$0.slug == intent.workflow \}\)' "workflow do chat não é validado contra os existentes"
hasF "$RULES" 'workflow deve conter seu slug se existente' "intentPrompt não pede o slug do workflow explícito"
finish
