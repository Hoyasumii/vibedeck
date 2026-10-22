#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# Execução por workflow recebe referência recuperável da ideia
w=$(block "$RULES" 'static func workflowInput(')
grep -q 'idea.id.uuidString' <<<"$w" || { echo "$RULES: workflowInput não inclui o UUID da ideia"; bad=1; }
grep -q 'get_idea' <<<"$w" || { echo "$RULES: workflowInput não indica como recuperar a ideia (get_idea)"; bad=1; }
grep -qi 'regras' <<<"$w" || { echo "$RULES: workflowInput não orienta a ler as regras"; bad=1; }
r=$(awk '/^pub fn workflow_input\(/{f=1} f{print} f&&/^}/{exit}' "$IDEAS_RS")
grep -q 'idea.id' <<<"$r" || { echo "$IDEAS_RS: workflow_input não inclui o UUID da ideia"; bad=1; }
grep -q 'get_idea' <<<"$r" || { echo "$IDEAS_RS: workflow_input não indica get_idea"; bad=1; }
grep -qi 'regras' <<<"$r" || { echo "$IDEAS_RS: workflow_input não orienta a ler as regras"; bad=1; }
inblock "$MODEL" 'func prepareIdeaImplementation(' 'startRun\(workflowSlug, input: IdeaImplementation.workflowInput\(idea\)' "prepareIdeaImplementation não passa workflowInput como entrada"
# A ideia é resolvida por UUID (slug, UUID ou título) no gate de implementação.
inblock "$CORESTORE" 'func implementableIdea' 'uuidString.lowercased\(\) == needle' "implementableIdea não resolve a ideia por UUID"
grep -qE 'fn resolve_idea|pub fn idea_detail' "$IDEAS_RS" || { echo "$IDEAS_RS: resolução da ideia por referência ausente"; bad=1; }
finish
