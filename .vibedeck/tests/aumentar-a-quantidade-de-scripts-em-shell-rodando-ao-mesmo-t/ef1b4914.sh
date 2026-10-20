#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $RE 'onEvent must never run concurrently' "falta o teste de reentrada"
hasF $RE 'if !inside.try()' "o callback do teste deve detectar reentrada"
before $PS 'state\.lock\(\)$' 'onEvent\(\.finished' "o .finished deve ser entregue com o lock do estado tomado"
hasF $PS 'onEvent(.started(' "o .started deve ser entregue pelo laço (com o lock do estado)"
finish
