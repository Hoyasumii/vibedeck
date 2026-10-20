#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $RT 'var text = command' "a detecção deve partir da própria string do comando"
hasF $RT 'return keys(in: text)' "a detecção deve cair na string do comando quando não há arquivo"
hasF $RTT 'BuildToolLock.keys(command: "swift test --filter X", root: FileManager.default.temporaryDirectory) == ["swift"]' "falta o teste com comando inline"
finish
