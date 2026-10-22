#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# promote_idea sincroniza sem duplicar (regras por id) e repromover não cria <slug>-2.
applies '(^|/)(crates/vibedeck-core/(src|tests)/|Tests/)'
grep -q '\.filter(|r| !known.contains(&r.id))' crates/vibedeck-core/src/ideas.rs || { echo "crates/vibedeck-core/src/ideas.rs: promote_idea deve acrescentar só as regras cujo id ainda não está no tópico"; exit 1; }
cargo_tests vibedeck-core promote_creates_topic_syncs_and_unpromotes promote_keeps_closed_status_and_topic_slug_is_unique promotion_copies_and_merges_paths
