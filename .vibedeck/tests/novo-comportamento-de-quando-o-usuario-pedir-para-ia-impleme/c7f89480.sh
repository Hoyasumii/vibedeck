#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# Confirmação revalida a elegibilidade com o conteúdo atual
c=$(block "$MODEL" 'func currentImplementationIdea(')
grep -q 'store.implementableIdea' <<<"$c" || { echo "$MODEL: currentImplementationIdea não relê a ideia no Core"; bad=1; }
g=$(block "$CORESTORE" 'func implementableIdea(')
grep -q 'listIdeas()' <<<"$g" || { echo "$CORESTORE: implementableIdea não relê as ideias"; bad=1; }
grep -q 'IdeaImplementation.isEligible' <<<"$g" || { echo "$CORESTORE: implementableIdea não revalida a elegibilidade"; bad=1; }
inblock "$MODEL" 'func prepareIdeaImplementation(' 'currentImplementationIdea\(id\)' "prepareIdeaImplementation não revalida antes de iniciar"
inblock "$SHEET" 'private func confirm(restart: Bool)' 'model.currentImplementationIdea\(request.ideaID\)' "confirm não revalida"
inblock "$SHEET" 'private func finish(' 'model.currentImplementationIdea\(request.ideaID\)' "finish não revalida"
# O Core Rust tem o mesmo gate (is_eligible) e teste.
has "$IDEAS_RS" 'pub fn implementable_idea' "Core: implementable_idea ausente"
rtest "$IDEAS_T" implementable_gate_requires_current_viable_verdict
finish
