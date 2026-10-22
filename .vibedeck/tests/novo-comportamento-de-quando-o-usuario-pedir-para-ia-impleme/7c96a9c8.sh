#!/usr/bin/env bash
# Pedido no chat sem modo explícito aguarda a escolha
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# send: com ideias no projeto, o texto passa pela classificação antes de ir à conversa
s=$(block "$SESSION" 'func send(_ text: String')
grep -q 'guard !isWorking, ideaRequest == nil else { return }' <<<"$s" || { echo "$SESSION: send não bloqueia enquanto há pedido de modo pendente"; bad=1; }
grep -q 'inspectIdeaRequest(text, mentions: mentions, attachments: attachments)' <<<"$s" || { echo "$SESSION: send não classifica o pedido"; bad=1; }
python3 -I - "$SESSION" <<'PY' || bad=1
import sys
s=open(sys.argv[1]).read()
i=s.find("func send(_ text: String"); body=s[i:]
a=body.find("inspectIdeaRequest("); b=body.find("if current == nil")
if a<0 or b<0 or a>b: print(sys.argv[1]+": inspectIdeaRequest deve ocorrer antes de abrir/enviar a conversa"); sys.exit(1)
PY
# A classificação é somente leitura e, com ideia reconhecida, abre o pedido em vez de enviar
inblock "$SESSION" 'private func inspectIdeaRequest' 'AIReadOnlyOperation\.run' "classificação deve ser somente leitura (AIReadOnlyOperation)"
seg=$(segment "$SESSION" 'if intent.mode != .none, let ref = intent.idea {' '} else {')
grep -q 'ideaRequest = IdeaRequest(ideaID: idea.id, mode: intent.mode, workflow: intent.workflow)' <<<"$seg" || { echo "$SESSION: pedido de implementação não abre ideaRequest"; bad=1; }
if grep -nE 'send\(|ask\(|startRun|prepareIdeaImplementation' <<<"$seg"; then echo "$SESSION: pedido de implementação executa antes da escolha"; bad=1; fi
hasF "$RULES" 'mode=ask quando não indicou o modo' "intentPrompt não define mode=ask para pedidos sem modo"
# Na folha, modo .ask não confirma automaticamente
t=$(block "$SHEET" '.task {')
grep -q 'if request.mode == .standard { confirm(restart: false) }' <<<"$t" || { echo "$WFV: .task deve confirmar apenas no modo standard explícito"; bad=1; }
[ "$(grep -c 'confirm(' <<<"$t")" = 1 ] || { echo "$WFV: .task confirma fora do modo standard"; bad=1; }
tests 'RuleDiscoverTests/implementationIntentContractSeparatesExplicitModesFromQuestions' implementationIntentContractSeparatesExplicitModesFromQuestions
finish
