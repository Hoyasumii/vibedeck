#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $RT '("node", #"\b(npm|npx|yarn|pnpm)\s+\S"#)' "npm/npx/yarn/pnpm devem ter a mesma chave"
hasF $RTT 'for command in ["npm test", "pnpm test", "yarn lint", "npx tsc"] { #expect(BuildToolLock.keys(in: command) == ["node"]) }' "falta o teste da chave compartilhada"
finish
