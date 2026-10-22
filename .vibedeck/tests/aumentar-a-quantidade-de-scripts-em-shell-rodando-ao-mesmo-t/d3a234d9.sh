#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $RUN '("node", r"\b(npm|npx|yarn|pnpm)\s+\S")' "npm/npx/yarn/pnpm devem ter a mesma chave"
hasF $RUN 'BuildToolLock::keys_in("cargo test && npm run x")' "falta o teste que cobre a chave node"
finish
