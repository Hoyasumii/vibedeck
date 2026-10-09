#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
need $G 'guard state != \.running' "GraphRunner não impede disparo concorrente"
need $G 'func cancel' "cancelamento ausente"
need $G 'ProgressView' "progresso ausente"
need $G 'failed\(' "estado de falha ausente"
need $G 'Cancelar' "botão de cancelar ausente"
# Uma execução por projeto: o runner precisa viver fora da view (ProjectModel), senão fechar/reabrir a aba perde o estado.
forbid $G '@State private var runner' "GraphRunner é @State da view: fechar/reabrir a aba ou abrir outra aba permite uma segunda execução no mesmo projeto"
exit $fail
