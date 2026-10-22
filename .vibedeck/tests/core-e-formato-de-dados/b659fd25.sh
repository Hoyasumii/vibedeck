#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# delete_topic solta as ideias órfãs (release_orphaned_ideas); remover regra solta do tópico não despromove.
applies '(^|/)(crates/vibedeck-core/(src|tests)/|Tests/)'
grep -A6 'pub fn delete_topic' crates/vibedeck-core/src/rules/topics.rs | grep 'release_orphaned_ideas' >/dev/null || { echo "crates/vibedeck-core/src/rules/topics.rs: delete_topic não chama release_orphaned_ideas"; exit 1; }
grep -A8 'pub fn delete_rule' crates/vibedeck-core/src/rules/topics.rs | grep 'release_orphaned' >/dev/null && { echo "crates/vibedeck-core/src/rules/topics.rs: delete_rule não deve despromover ideias"; exit 1; }
cargo_tests vibedeck-core orphaned_ideas_are_released_when_topic_disappears promote_creates_topic_syncs_and_unpromotes
