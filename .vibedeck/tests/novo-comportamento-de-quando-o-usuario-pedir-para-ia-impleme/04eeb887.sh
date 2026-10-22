#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# Retomar continua a execução do estado persistido
hasF "$SHEET" 'LoggedButton("Retomar") { confirm(restart: false) }' "Retomar deve confirmar com restart: false"
i=$(block "$MODEL" 'func prepareIdeaImplementation(')
grep -q 'if let existing, !restart {' <<<"$i" || { echo "$MODEL: Retomar (restart == false) deve tratar a execução existente"; bad=1; }
grep -q 'store.resumeRun(existing.slug)' <<<"$i" || { echo "$MODEL: Retomar não usa resumeRun na execução existente"; bad=1; }
f=$(block "$SHEET" 'private func finish(')
grep -q 'restart: pendingRestart' <<<"$f" || { echo "$WFV: finish não repassa a escolha Retomar/Reiniciar"; bad=1; }
# Core: resume_run mantém etapa atual, histórico e contadores; só reabre execução parada.
r=$(awk '/^pub fn resume_run\(/{f=1} f{print} f&&/^}/{exit}' "$WFOPS")
[ -n "$r" ] || { echo "$WFOPS: resume_run não encontrado"; bad=1; }
grep -q 'run.current = ' <<<"$r" && { echo "$WFOPS: resume_run não pode mexer na etapa atual"; bad=1; }
grep -q 'run.history' <<<"$r" && { echo "$WFOPS: resume_run não pode mexer no histórico"; bad=1; }
finish
