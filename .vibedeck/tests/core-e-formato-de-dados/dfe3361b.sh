#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# SchemaURL.base é a única base do worker de schemas em Sources, schema e README.md.
applies '(^|/)(Sources/|schema/|README\.md|scripts/set-schema-url\.sh)'
base=$(grep -m1 'public static let base' Sources/VibeDeckCore/Models.swift | sed -E 's/.*"(https?:\/\/[^"]*)\/v1".*/\1/')
[ -n "$base" ] || { echo "Sources/VibeDeckCore/Models.swift: SchemaURL.base não encontrada"; exit 1; }
bad=0
# Toda URL de schema (vibedeck-schema.*workers.dev) precisa começar com a base; skill-icons é outro worker.
while IFS= read -r hit; do
  url=$(printf '%s' "$hit" | grep -oE 'https://[A-Za-z0-9.-]*workers\.dev' | head -1)
  case "$hit" in *skill-icons*) continue;; esac
  [ "$url" = "$base" ] || { echo "${hit%%:*}: base de schema diferente de SchemaURL.base ($base): $url"; bad=1; }
done < <(grep -rnE 'https://[A-Za-z0-9.-]*workers\.dev' Sources schema README.md 2>/dev/null | grep -v 'skill-icons' | sed -E 's/^([^:]+:[0-9]+):.*(https:\/\/[A-Za-z0-9.-]*workers\.dev).*/\1:\2/')
exit $bad
