#!/usr/bin/env bash
# Identidade da execução estável quando título/descrição mudam
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
w=$(block "$RULES" 'public static func workflowInput(')
if grep -nE 'idea\.(title|body|rules|tags|contentFingerprint|readiness|updatedAt)' <<<"$w"; then echo "$RULES: workflowInput depende de conteúdo mutável da ideia"; bad=1; fi
inblock "$RUNS" 'public func ideaRun(' 'IdeaImplementation.workflowInput\(idea\)' "ideaRun deve localizar pela entrada estável"
inblock "$RUNS" 'public func ideaRun(' 'run.input == input' "ideaRun deve comparar a entrada da execução"
tests 'WorkflowRunsTests/ideaRunIdentitySurvivesEditsAndResumePreservesProgress' ideaRunIdentitySurvivesEditsAndResumePreservesProgress
finish
