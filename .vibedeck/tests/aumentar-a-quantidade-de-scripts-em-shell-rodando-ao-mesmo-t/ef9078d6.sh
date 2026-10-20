#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'state.running -= 1' "a vaga deve ser liberada ao fim do script"
hasF $PS 'state.busy.subtract(job.locks)' "a trava da ferramenta deve ser liberada ao fim do script"
before $PS 'runner\.run\(job\.command' 'state\.running -= 1' "a liberação deve vir depois do runner, sem caminho de saída antes"
hasF $RE 'for code in [ShellRunner.timedOutStatus, 127]' "o teste deve cobrir timeout e erro 127"
hasF $RE 'runs.map(\.command) == ["fail", "next", "last"]' "o teste deve exigir que o script seguinte inicie"
finish
