#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
l=$(grep -n 'runScripts(candidates' $PS || true)
[ -n "$l" ] || { echo "$PS: submitCheck não chama runScripts(candidates…)"; bad=1; }
none $PS 'runScripts\(candidates[^\n]*(stopOnMustFailure|cancellation)' "submitCheck não pode parar na falha must"
hasF $RE '// submitCheck answers every rule, even after a failed must.' "falta o teste de submitCheck"
hasF $RE 'check.results.filter { $0.source == .script }.map(\.ruleId)' "o teste deve exigir resultado .script para toda regra"
finish
