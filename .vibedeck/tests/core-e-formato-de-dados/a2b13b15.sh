#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# unpromote_idea apaga o tópico vinculado, solta a ideia (approved → exploring) e mantém idea.rules; release_orphaned_ideas é idempotente.
applies '(^|/)(crates/vibedeck-core/(src|tests)/|Tests/)'
f=crates/vibedeck-core/src/ideas.rs
grep -A14 'pub fn unpromote_idea' "$f" | grep 'delete_rule_topic' >/dev/null || { echo "$f: unpromote_idea deve apagar o tópico vinculado"; exit 1; }
grep -A12 'fn release(' "$f" | grep -q 'promoted_topic = None' || { echo "$f: release deve zerar promoted_topic"; exit 1; }
grep -A12 'fn release(' "$f" | grep -q 'IdeaStatus::Exploring' || { echo "$f: release deve voltar approved para exploring"; exit 1; }
cargo_tests vibedeck-core promote_creates_topic_syncs_and_unpromotes orphaned_ideas_are_released_when_topic_disappears
