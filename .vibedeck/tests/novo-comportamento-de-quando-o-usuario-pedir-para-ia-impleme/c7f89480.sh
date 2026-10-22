#!/usr/bin/env bash
# Confirmação revalida a elegibilidade com o conteúdo atual
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
c=$(block "$MODEL" 'func currentImplementationIdea(')
grep -q 'let idea = try store.loadIdea(slug)' <<<"$c" || { echo "$MODEL: currentImplementationIdea não relê a ideia do disco"; bad=1; }
grep -q 'guard IdeaImplementation.isEligible(idea) else' <<<"$c" || { echo "$MODEL: currentImplementationIdea não revalida a elegibilidade"; bad=1; }
inblock "$MODEL" 'func prepareIdeaImplementation(' 'let \(slug, idea\) = try currentImplementationIdea\(id\)' "prepareIdeaImplementation não revalida antes de iniciar"
inblock "$SHEET" 'private func confirm(restart: Bool)' 'model.currentImplementationIdea\(request.ideaID\)' "confirm não revalida"
inblock "$SHEET" 'private func finish(' 'model.currentImplementationIdea\(request.ideaID\)' "finish não revalida"
inblock "$RUNS" 'public func implementIdeaRun(' 'guard IdeaImplementation.isEligible\(idea\) else' "implementIdeaRun não revalida"
tests 'IdeaEvaluationTests/confirmationReadsDiskEvenBeforeWatcherDeliversExternalEdit|WorkflowRunsTests/ideaRunRejectsExternallyInvalidatedAssessmentWithoutWrites' confirmationReadsDiskEvenBeforeWatcherDeliversExternalEdit ideaRunRejectsExternallyInvalidatedAssessmentWithoutWrites
finish
