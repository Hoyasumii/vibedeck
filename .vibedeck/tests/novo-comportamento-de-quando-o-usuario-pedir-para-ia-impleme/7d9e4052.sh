#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# Reiniciar começa pela etapa inicial do workflow
hasF "$SHEET" 'LoggedButton("Reiniciar") { confirm(restart: true) }' "Reiniciar deve confirmar com restart: true"
i=$(block "$MODEL" 'func prepareIdeaImplementation(')
grep -q 'restart' <<<"$i" || { echo "$MODEL: prepareIdeaImplementation ignora restart"; bad=1; }
# O Core só volta à etapa inicial de uma execução em andamento/parada quando `from` é informado:
# start_run com a mesma entrada retoma (engine::restart sai cedo se a execução não terminou e não há `from`).
grep -q 'if !run.is_finished() && target.is_none()' "$WFENGINE" && \
  ! grep -qE 'startRun\([^)]*from:' <<<"$i" && \
  { echo "$MODEL: Reiniciar usa startRun sem 'from:'; o Core (start_run) manteria a execução em andamento na etapa atual. Passe from: <primeira etapa> ao reiniciar."; bad=1; }
r=$(awk '/^pub fn restart_from_beginning\(/{f=1} f{print} f&&/^}/{exit}' "$WFENGINE")
grep -q 'workflow.steps.first()' <<<"$r" || { echo "$WFENGINE: restart_from_beginning não usa a primeira etapa"; bad=1; }
grep -q 'run.current = Some(first)' <<<"$r" || { echo "$WFENGINE: restart_from_beginning não move a etapa atual para a inicial"; bad=1; }
finish
