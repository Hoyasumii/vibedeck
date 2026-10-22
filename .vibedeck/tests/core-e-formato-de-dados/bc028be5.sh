#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# submit_check: script decide as regras de script; manuais sem resposta (verify_manual) → IncompleteCheck; passed = nenhuma must em fail.
applies '(^|/)(crates/vibedeck-core/src/rules/|crates/vibedeck/(src|tests)/|crates/vibedeck-core/tests/)'
f=crates/vibedeck-core/src/rules/tasks.rs
fail=0
bad() { echo "$1"; fail=1; }
grep -q 'return Err(RuleError::IncompleteCheck(missing))' "$f" || bad "$f: submit_check deve lançar IncompleteCheck listando as regras sem resposta"
grep -q 'if !missing.is_empty() && params.verify_manual' "$f" || bad "$f: IncompleteCheck só com verify_manual (manuais); scripts decidem sozinhos"
grep -q 'passed: failures.is_empty()' "$f" || bad "$f: passed deve ser 'nenhuma must em fail'"
grep -q '\.filter(|r| r.severity == RuleSeverity::Should)' "$f" || bad "$f: should em fail deve virar warning"
grep -q '\.filter(|r| r.severity == RuleSeverity::Must)' "$f" || bad "$f: must em fail deve virar failure"
grep -q 'a.verdict == RuleVerdict::Fail' "$f" || bad "$f: só veredito fail conta como falha (na conta como respondida)"
[ $fail -eq 0 ] || exit 1
cargo_tests vibedeck check_runs_scripts_and_records failed_must_script_reports_output
