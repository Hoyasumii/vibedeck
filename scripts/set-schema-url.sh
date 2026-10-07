#!/usr/bin/env bash
# Points every reference to the JSON Schemas at the deployed worker.
#   scripts/set-schema-url.sh https://vibedeck-schema.<you>.workers.dev
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?usage: $0 <base-url-without-/v1>}"
NEW="${NEW%/}"
OLD="$(grep -m1 'public static let base' Sources/VibeDeckCore/Models.swift | sed -E 's/.*"(.*)\/v1".*/\1/')"
grep -rl --null "$OLD" Sources schema README.md 2>/dev/null | xargs -0 sed -i '' "s#$OLD#$NEW#g"
echo "Schema base: $OLD → $NEW"
