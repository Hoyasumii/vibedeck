#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# SCHEMA_BASE (crates/vibedeck-core/src/model/project.rs) é a única base do worker de schemas no Core, no app, nos schemas, no README.md e no guia.
applies '(^|/)(crates/|Sources/|schema/|README\.md|scripts/set-schema-url\.sh|\.vibedeck/guide\.md)'
base=$(grep -m1 'pub const SCHEMA_BASE' crates/vibedeck-core/src/model/project.rs | sed -E 's/.*"(https?:\/\/[^"]*)\/v1".*/\1/')
[ -n "$base" ] || { echo "crates/vibedeck-core/src/model/project.rs: SCHEMA_BASE não encontrada"; exit 1; }
bad=0
# Toda URL de schema (workers.dev) precisa começar com a base; skill-icons é outro worker.
while IFS= read -r hit; do
  url=$(printf '%s' "$hit" | grep -oE 'https://[A-Za-z0-9.-]*workers\.dev' | head -1)
  [ "$url" = "$base" ] || { echo "${hit%%:*}: base de schema diferente de SCHEMA_BASE ($base): $url"; bad=1; }
done < <(grep -rnE 'https://[A-Za-z0-9.-]*workers\.dev' crates Sources schema README.md .vibedeck/guide.md 2>/dev/null | grep -v 'skill-icons' | sed -E 's/^([^:]+:[0-9]+):.*(https:\/\/[A-Za-z0-9.-]*workers\.dev).*/\1:\2/')
exit $bad
