#!/usr/bin/env bash
# Reiniciar começa pela etapa inicial do workflow
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
hasF "$SHEET" 'LoggedButton("Reiniciar") { confirm(restart: true) }' "Reiniciar deve confirmar com restart: true"
i=$(block "$RUNS" 'public func implementIdeaRun(')
grep -q 'WorkflowRunEngine.restartFromBeginning(&run, workflow: loadWorkflow(run.workflow))' <<<"$i" || { echo "$RUNS: Reiniciar não usa restartFromBeginning"; bad=1; }
grep -q 'try saveRun(run, ref: existing.ref)' <<<"$i" || { echo "$RUNS: reinício não é persistido"; bad=1; }
r=$(block "$RUNS" 'public static func restartFromBeginning(')
grep -q 'workflow.steps.first?.id' <<<"$r" || { echo "$RUNS: restartFromBeginning não usa a primeira etapa"; bad=1; }
grep -q 'run.current = first' <<<"$r" || { echo "$RUNS: restartFromBeginning não move a etapa atual para a inicial"; bad=1; }
tests 'WorkflowRunsTests/ideaRunIdentitySurvivesEditsAndResumePreservesProgress' ideaRunIdentitySurvivesEditsAndResumePreservesProgress
finish
