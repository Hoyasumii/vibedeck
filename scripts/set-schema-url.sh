#!/usr/bin/env bash
# Points every reference to the JSON Schemas at the deployed worker.
#   scripts/set-schema-url.sh https://vibedeck-schema.<you>.workers.dev
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?usage: $0 <base-url-without-/v1>}"
NEW="${NEW%/}"
OLD="$(grep -m1 'SCHEMA_BASE: &str' crates/vibedeck-core/src/model/project.rs | sed -E 's/.*"(.*)\/v1".*/\1/')"
# `sed -i` differs between GNU and BSD (macOS): write through a temp suffix, which both accept.
grep -rl --null "$OLD" crates Sources schema README.md 2>/dev/null | xargs -0 sed -i.bak "s#$OLD#$NEW#g"
find crates Sources schema README.md -name '*.bak' -delete 2>/dev/null || true
echo "Schema base: $OLD → $NEW"
