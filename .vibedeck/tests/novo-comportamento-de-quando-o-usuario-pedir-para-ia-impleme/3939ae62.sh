#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# Elegibilidade: approved + readiness.viable + fingerprint atual
b=$(block "$RULES" "static func isEligible")
grep -q 'idea.status == .approved' <<<"$b" || { echo "$RULES: isEligible não exige status approved"; bad=1; }
grep -q 'idea.readiness?.viable == true' <<<"$b" || { echo "$RULES: isEligible não exige readiness.viable == true"; bad=1; }
grep -q 'idea.readiness?.fingerprint == idea.contentFingerprint' <<<"$b" || { echo "$RULES: isEligible não compara readiness.fingerprint com contentFingerprint"; bad=1; }
if grep -q '||' <<<"$b"; then echo "$RULES: isEligible usa '||' (todas as condições são obrigatórias)"; bad=1; fi
r=$(awk '/^pub fn is_eligible\(/{f=1} f{print} f&&/^}/{exit}' "$IDEAS_RS")
grep -q 'IdeaStatus::Approved' <<<"$r" || { echo "$IDEAS_RS: is_eligible não exige status approved"; bad=1; }
grep -q 'r.viable' <<<"$r" || { echo "$IDEAS_RS: is_eligible não exige readiness.viable"; bad=1; }
grep -q 'r.fingerprint == idea.content_fingerprint()' <<<"$r" || { echo "$IDEAS_RS: is_eligible não compara o fingerprint atual"; bad=1; }
if grep -q '||' <<<"$r"; then echo "$IDEAS_RS: is_eligible usa '||'"; bad=1; fi
# Pontos de entrada do modo usam o mesmo critério
hasF "$SESSION" 'guard !isWorking, IdeaImplementation.isEligible(idea) else { return }' "requestIdeaImplementation não checa isEligible"
hasF "$IDEAV" 'if IdeaImplementation.isEligible(current) {' "Implementar não decide o modo por isEligible"
rtest "$IDEAS_T" implementable_gate_requires_current_viable_verdict
finish
