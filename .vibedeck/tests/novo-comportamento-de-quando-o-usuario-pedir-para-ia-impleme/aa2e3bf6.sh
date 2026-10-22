#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# Identidade da execução estável quando título/descrição mudam
w=$(block "$RULES" 'static func workflowInput(')
if grep -nE 'idea\.(title|body|rules|tags|contentFingerprint|readiness|updatedAt)' <<<"$w"; then echo "$RULES: workflowInput depende de conteúdo mutável da ideia"; bad=1; fi
r=$(awk '/^pub fn workflow_input\(/{f=1} f{print} f&&/^}/{exit}' "$IDEAS_RS")
if grep -nE 'idea\.(title|body|rules|tags|content_fingerprint|readiness|updated_at)' <<<"$r"; then echo "$IDEAS_RS: workflow_input depende de conteúdo mutável da ideia"; bad=1; fi
inblock "$MODEL" 'func ideaRun(' 'IdeaImplementation.workflowInput\(idea\)' "ideaRun deve localizar pela entrada estável"
inblock "$MODEL" 'func ideaRun(' '\$0.value.input == input' "ideaRun deve comparar a entrada da execução"
# O Core nomeia a execução pela entrada: mesma ideia + workflow => mesma execução.
grep -q 'Some(i) => slug::make(i)' "$WFOPS" || { echo "$WFOPS: start_run deve nomear a execução pela entrada"; bad=1; }
finish
