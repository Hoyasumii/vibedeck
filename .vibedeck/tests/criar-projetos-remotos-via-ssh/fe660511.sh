#!/usr/bin/env bash
# FE660511: edições não sincronizadas ficam em disco (cache + snapshot confirmado) e sobrevivem a reinício.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $CONN 'AILocalStore.machineDirectory("SSH")' "o cache SSH deve ficar no Application Support"
forbid $WS 'temporaryDirectory' "o cache de pendências não pode ficar em pasta temporária"
in_body $WS 'private func persist\(\)' 'AtomicFile\.write' "o snapshot confirmado deve ser gravado de forma atômica"
in_body $WS 'public var pendingCount' 'localSnapshot\(root\)' "pendências devem ser calculadas a partir dos arquivos em disco"
in_body $WS 'public static func existing' 'ssh-workspace\.json' "o estado deve ser recuperado do disco ao reabrir"
run_tests durableEditsDeletionAndRestart failedUploadRetainsDurablePendingAndBase
finish
