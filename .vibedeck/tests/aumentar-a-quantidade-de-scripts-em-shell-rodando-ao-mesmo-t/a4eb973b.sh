#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $RUN 'let mut text = command.to_string();' "a detecção deve partir da própria string do comando"
hasF $RUN 'Self::keys_in(&text)' "a detecção deve cair na string do comando quando não há arquivo"
hasF $RUN 'BuildToolLock::keys_in("swift build -c release"), ["swift"]' "falta o teste com comando inline"
finish
