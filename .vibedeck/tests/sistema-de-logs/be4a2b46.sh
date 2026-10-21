#!/usr/bin/env bash
# Mudança externa aplicada ao vivo pelo app registra info store.external_changed com file relativo e origin=external.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckApp/ProjectModel\.swift$|^Sources/VibeDeckCore/Logging\.swift$'
P=Sources/VibeDeckApp/ProjectModel.swift
blk=$(region "$P" 'func handleExternalChanges' '^    }$')
fail=0
bad() { echo "$1"; fail=1; }
printf '%s' "$blk" | grep 'VDLog.info("store.external_changed"' >/dev/null || bad "$P: handleExternalChanges deve gravar info store.external_changed"
printf '%s' "$blk" | grep 'component: .app' >/dev/null || bad "$P: store.external_changed deve ter component .app"
printf '%s' "$blk" | grep '"file": String(url.dropFirst(prefix.count))' >/dev/null || bad "$P: context.file deve ser relativo à raiz do projeto"
printf '%s' "$blk" | grep '"origin": "external"' >/dev/null || bad "$P: context.origin deve ser external"
# Escritas do próprio app são ignoradas (não viram 'external').
printf '%s' "$blk" | grep 'current == lastWritten\[url\]' >/dev/null || bad "$P: gravações do próprio app precisam ser filtradas antes do log"
[ $fail -eq 0 ] || exit 1
