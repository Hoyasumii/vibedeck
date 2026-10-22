#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# rules::glob::matches: sem / casa o nome em qualquer profundidade; / inicial ancora; / final casa abaixo; * não cruza /; ** atravessa.
applies '(^|/)(crates/vibedeck-core/(src|tests)/|Tests/)'
cargo_tests vibedeck-core globs
