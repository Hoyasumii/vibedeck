#!/usr/bin/env bash
# B9E0F0E2: sem escolha do usuário, nem a versão remota nem a local de um conflito são sobrescritas.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $SHEET 'LoggedButton("Decidir depois", role: .cancel) { conflict = nil }' "fechar o conflito não pode escolher versão"
needF $WS 'guard stateLock.withLock({ conflictFiles[path] == nil }) else { continue }' "arquivo em conflito não pode ser enviado automaticamente"
needF $WS 'conflicts: conflictFiles.isEmpty ? nil : conflictFiles' "conflitos devem persistir em disco"
run_tests unresolvedConflictNeverOverwritesEitherVersion conflictPreservesBothAcrossRestartUntilChoice
finish
