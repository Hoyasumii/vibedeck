#!/usr/bin/env bash
# Regras de ideia não promovida nunca entram em rules_for/checks; promover cria tópico, sincronizar não duplica,
# apagar o tópico despromove (vínculo some, approved → exploring, rascunhos ficam).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^crates/'
fail=0
bad() { echo "$1"; fail=1; }
T=crates/vibedeck-core/src/rules/topics.rs
# applicable_topics só lê tópicos reais (rules/*.json), nunca ideias.
body=$(awk '/pub fn applicable_topics\(/{f=1} f{print} f&&/^}$/{exit}' "$T")
[ -n "$body" ] || bad "$T: applicable_topics não encontrada"
echo "$body" | grep 'list_topics(store)' >/dev/null || bad "$T: applicable_topics não parte de list_topics"
echo "$body" | grep -iE 'idea' >/dev/null && bad "$T: applicable_topics consulta ideias"
# tarefas/checks (tasks.rs), rules_for (MCP/CLI) e submit_rule_check não leem ideias.
for f in crates/vibedeck-core/src/rules/tasks.rs crates/vibedeck-core/src/rules/checklist.rs crates/vibedeck/src/mcp/tools/rules.rs crates/vibedeck/src/cli/rules.rs; do
  hits=$(sed '/#\[cfg(test)\]/,$d' "$f" | grep -nE '\bIdea\b|\bideas\(\)|list_ideas|load::<Idea>|idea_pairs|\.ideas\b' || true)
  [ -z "$hits" ] || { echo "$hits" | sed "s|^|$f:|; s|\$|  <- rules_for/check lê ideias|"; fail=1; }
done
grep -q 'applicable_topics' crates/vibedeck/src/mcp/tools/rules.rs || bad "crates/vibedeck/src/mcp/tools/rules.rs: rules_for não usa applicable_topics"
[ $fail -eq 0 ] || exit 1
cargo_tests vibedeck-core promote_creates_topic_syncs_and_unpromotes orphaned_ideas_are_released_when_topic_disappears applicable_topics_by_scope
