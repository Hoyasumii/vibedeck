#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
# Os scripts rodam numa única chamada ao Core (run_rule_tests); só depois dela entra o bloco withAI.
f=$(lineof $MODEL 'call\("run_rule_tests"')
w=$(lineof $MODEL 'if withAI \{' "${f:-0}")
[ -n "$f" ] && [ -n "$w" ] && [ "$f" -lt "$w" ] || { echo "$MODEL: o bloco withAI deve vir depois do fim da chamada run_rule_tests (linhas ${f:-?}/${w:-?})"; bad=1; }
hasF $MODEL 'let scriptResults = execution.steps.compactMap(\.result)' "a IA deve receber os resultados dos scripts"
hasF $MODEL 'try await verify(store.root, provider, entry.topic, entry.slug, rules, scriptResults)' "verify deve receber scriptResults"
finish
