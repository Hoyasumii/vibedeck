#!/usr/bin/env bash
# Execução por workflow recebe referência recuperável da ideia
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
w=$(block "$RULES" 'public static func workflowInput(')
grep -q 'idea.id.uuidString' <<<"$w" || { echo "$RULES: workflowInput não inclui o UUID da ideia"; bad=1; }
grep -q 'get_idea' <<<"$w" || { echo "$RULES: workflowInput não indica como recuperar a ideia (get_idea)"; bad=1; }
grep -qi 'regras' <<<"$w" || { echo "$RULES: workflowInput não orienta a ler as regras"; bad=1; }
inblock "$RUNS" 'public func implementIdeaRun(' 'startRun\(workflow, input: IdeaImplementation.workflowInput\(idea\)' "implementIdeaRun não passa workflowInput como entrada"
has Sources/VibeDeckCore/ProjectStore.swift 'func resolveIdeaSlug' "resolveIdeaSlug (resolução por UUID) ausente"
tests 'WorkflowRunsTests/ideaRunIdentitySurvivesEditsAndResumePreservesProgress' ideaRunIdentitySurvivesEditsAndResumePreservesProgress
finish
