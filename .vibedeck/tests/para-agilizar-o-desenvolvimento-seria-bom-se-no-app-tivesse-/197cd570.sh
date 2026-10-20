#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
T=Tests/VibeDeckCoreTests
# Coverage may move between suites; require both prompt branches across current tests.
fail() { echo "$1" >&2; exit 1; }
grep -rq "IdeaImplementation.prompt" "$T" || fail "$T: nenhum teste de IdeaImplementation.prompt"
grep -rE "IdeaImplementation.prompt\(.*topic: nil" "$T" >/dev/null || fail "$T: falta caso com topic: nil"
grep -rE "IdeaImplementation.prompt\(.*topic: \"" "$T" >/dev/null || fail "$T: falta caso com topic não nil"
exit 0
