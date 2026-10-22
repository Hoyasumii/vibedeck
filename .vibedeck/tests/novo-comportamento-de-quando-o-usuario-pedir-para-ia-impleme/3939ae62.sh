#!/usr/bin/env bash
# Elegibilidade: approved + readiness.viable + fingerprint atual
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
b=$(block "$RULES" "public static func isEligible")
grep -q 'idea.status == .approved' <<<"$b" || { echo "$RULES: isEligible não exige status approved"; bad=1; }
grep -q 'idea.readiness?.viable == true' <<<"$b" || { echo "$RULES: isEligible não exige readiness.viable == true"; bad=1; }
grep -q 'idea.readiness?.fingerprint == idea.contentFingerprint' <<<"$b" || { echo "$RULES: isEligible não compara readiness.fingerprint com contentFingerprint"; bad=1; }
if grep -q '||' <<<"$b"; then echo "$RULES: isEligible usa '||' (todas as condições são obrigatórias)"; bad=1; fi
# Pontos de entrada do modo usam o mesmo critério
hasF "$SESSION" 'guard !isWorking, IdeaImplementation.isEligible(idea) else { return }' "requestIdeaImplementation não checa isEligible"
hasF "$IDEAV" 'if IdeaImplementation.isEligible(current) {' "Implementar não decide o modo por isEligible"
tests 'RuleDiscoverTests/implementationModeRequiresApprovedAndCurrentViableAssessment' implementationModeRequiresApprovedAndCurrentViableAssessment
finish
