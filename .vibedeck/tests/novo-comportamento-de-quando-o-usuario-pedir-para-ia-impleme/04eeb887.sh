#!/usr/bin/env bash
# Retomar continua a execução do estado persistido
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
hasF "$SHEET" 'LoggedButton("Retomar") { confirm(restart: false) }' "Retomar deve confirmar com restart: false"
i=$(block "$RUNS" 'public func implementIdeaRun(')
grep -q 'if !restart { return (existing.ref, try resumeRun(existing.ref)) }' <<<"$i" || { echo "$RUNS: Retomar não usa resumeRun na execução existente"; bad=1; }
f=$(block "$SHEET" 'private func finish(')
grep -q 'restart: pendingRestart' <<<"$f" || { echo "$WFV: finish não repassa a escolha Retomar/Reiniciar"; bad=1; }
tests 'WorkflowRunsTests/ideaRunIdentitySurvivesEditsAndResumePreservesProgress' ideaRunIdentitySurvivesEditsAndResumePreservesProgress
finish
