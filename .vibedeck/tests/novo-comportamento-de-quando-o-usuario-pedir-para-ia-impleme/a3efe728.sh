#!/usr/bin/env bash
# Execução padrão usa IdeaImplementation.prompt, sem execução de workflow
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
p=$(block "$MODEL" 'func prepareIdeaImplementation(')
grep -q 'return (IdeaImplementation.prompt(slug: slug, idea: idea, topic: topic), execution)' <<<"$p" || { echo "$MODEL: prepareIdeaImplementation não devolve IdeaImplementation.prompt"; bad=1; }
grep -q 'let execution = try workflow.map' <<<"$p" || { echo "$MODEL: execução de workflow deve depender de workflow != nil"; bad=1; }
f=$(block "$SHEET" 'private func finish(')
python3 -I - "$f" <<'PY' || bad=1
import sys
f=sys.argv[1]
i=f.find("if let execution = prepared.execution {"); e=f.find("} else {", i); a=f.find("session.ask(prepared.prompt, inspectIdeas: false)", e)
if min(i,e,a)<0: print("WorkflowView.swift: finish deve enviar prepared.prompt no ramo sem execução"); sys.exit(1)
PY
hasF "$SHEET" 'LoggedButton("Execução padrão") { confirm(restart: false) }' "Execução padrão deve confirmar sem workflow"
tests 'IdeaEvaluationTests/standardImplementationUsesSharedPromptAndUndoesPromotion' standardImplementationUsesSharedPromptAndUndoesPromotion
finish
