#!/usr/bin/env bash
# 80A692FB: o conflito mostra versão local e remota e permite escolher qual preservar.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $WS 'public let local: Data?' "o conflito deve guardar a versão local"
needF $WS 'public let remote: Data?' "o conflito deve guardar a versão remota"
needF $SHEET 'version("Versão local", data: item.local)' "a versão local deve ser exibida"
needF $SHEET 'version("Versão remota", data: item.remote)' "a versão remota deve ser exibida"
needF $SHEET 'status.resolve(item, keepLocal: true)' "falta 'Preservar local'"
needF $SHEET 'status.resolve(item, keepLocal: false)' "falta 'Preservar remota'"
needF $SHEET 'LoggedButton("Resolver: \(item.path)")' "cada conflito deve poder ser aberto"
run_tests conflictPreservesBothAcrossRestartUntilChoice chooseRemoteAndDetectChangedConflictVersion
finish
