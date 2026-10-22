#!/usr/bin/env bash
# Mudança externa aplicada ao vivo pelo app registra info store.external_changed com file relativo e origin=external.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckApp/(ProjectModel\.swift|Core/Support/Logging\.swift)$'
P=Sources/VibeDeckApp/ProjectModel.swift
blk=$(region "$P" 'func applyExternalChanges' '^    }$')
handler=$(region "$P" 'func handleExternalChanges' '^    }$')
fail=0
bad() { echo "$1"; fail=1; }
printf '%s' "$blk" | grep 'VDLog.info("store.external_changed"' >/dev/null || bad "$P: handleExternalChanges deve gravar info store.external_changed"
printf '%s' "$blk" | grep 'component: .app' >/dev/null || bad "$P: store.external_changed deve ter component .app"
printf '%s' "$blk" | grep '"file": String(url.dropFirst(prefix.count))' >/dev/null || bad "$P: context.file deve ser relativo à raiz do projeto"
printf '%s' "$blk" | grep '"origin": "external"' >/dev/null || bad "$P: context.origin deve ser external"
# Escritas do próprio app são ignoradas (não viram 'external').
# O Core não expõe eco por arquivo: a revisão do projeto (project_revision) guardada após cada gravação do app é o filtro.
printf '%s' "$handler" | grep 'isOwnEcho()' >/dev/null || bad "$P: handleExternalChanges deve ignorar o eco das gravações do app (isOwnEcho)"
printf '%s' "$handler" | grep 'logAsExternal: false' >/dev/null || bad "$P: durante gravações do app o evento não pode ser logado como external"
grep 'ownRevision = text' "$P" >/dev/null || bad "$P: a revisão após a gravação do app não é guardada (ownRevision)"
printf '%s' "$blk" | grep 'logAsExternal, url.hasPrefix(prefix)' >/dev/null || bad "$P: o log external deve respeitar logAsExternal"
[ $fail -eq 0 ] || exit 1
