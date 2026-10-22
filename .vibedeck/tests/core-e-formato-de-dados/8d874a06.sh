#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# applicable_topics = globais + os que casam com os arquivos (relativos à raiz) + explícitos.
applies '(^|/)(crates/vibedeck-core/(src|tests)/|Tests/)'
f=crates/vibedeck-core/src/rules/topics.rs
grep -q 'files.iter().map(|f| relative_path(store, f))' "$f" || { echo "$f: applicable_topics deve converter caminhos absolutos em relativos antes do glob"; exit 1; }
grep -q 'entry.value.is_global()' "$f" && grep -q 'named.contains(&entry.slug)' "$f" && grep -q 'entry.value.matches_file(f)' "$f" || { echo "$f: applicable_topics deve ser globais + explícitos + os que casam os arquivos"; exit 1; }
cargo_tests vibedeck-core applicable_topics_by_scope relative_path_cases
