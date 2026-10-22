#!/usr/bin/env bash
# E0AD947E: a pendência só é baixada após o servidor confirmar a gravação.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
B=$(body $WS 'public func synchronize\(using')
s=$(grep -nF 'try transport.replace(path, expected: server, with: local)' <<<"$B" | head -1 | cut -d: -f1)
a=$(grep -nF 'base[path] = local; try persist()' <<<"$B" | head -1 | cut -d: -f1)
if [ -z "$s" ] || [ -z "$a" ] || [ "$s" -ge "$a" ]; then echo "$WS (synchronize): a base só pode ser atualizada depois do envio confirmado"; fail=1; fi
in_body $WS 'public func replace\(' 'cmp -s " \+ quoted \+ " -"' "o envio deve conferir o conteúdo gravado no servidor"
run_tests failedUploadRetainsDurablePendingAndBase concurrentEditDuringUploadRemainsPending
finish
