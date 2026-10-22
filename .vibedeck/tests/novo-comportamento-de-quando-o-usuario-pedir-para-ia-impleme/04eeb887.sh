#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# Retomar continua a execução do estado persistido
hasF "$SHEET" 'LoggedButton("Retomar") { confirm(restart: false) }' "Retomar deve confirmar com restart: false"
i=$(block "$MODEL" 'func prepareIdeaImplementation(')
grep -q 'if let existing {' <<<"$i" || { echo "$MODEL: prepareIdeaImplementation deve tratar a execução existente"; bad=1; }
grep -qE 'if restart \{[^}]*restartRun\(existing\.slug\)[^}]*\} else \{ *run = try await store\.resumeRun\(existing\.slug\)' <<<"$i" \
  || { echo "$MODEL: Retomar (restart == false) deve usar store.resumeRun(existing.slug) na execução existente, sem iniciar outra"; bad=1; }
# Retomar nunca inicia execução nova quando já existe uma (startRun só no ramo sem execução existente).
awk '/if let existing \{/{f=1} /\} else \{/ && f{exit} f && /startRun\(/{print "x"}' <<<"$i" | grep -q x && { echo "$MODEL: Retomar não pode chamar startRun na execução existente"; bad=1; }
# CoreStore.resumeRun só reabre execução parada (workflow_run_resume); o resto volta como está.
CR=Sources/VibeDeckApp/Core/CoreStore+Runs.swift
r2=$(block "$CR" 'func resumeRun(')
grep -q 'guard run.status == .stopped, run.current != nil else { return run }' <<<"$r2" || { echo "$CR: resumeRun deve só reabrir execução parada"; bad=1; }
grep -q '"workflow_run_resume"' <<<"$r2" || { echo "$CR: resumeRun deve usar a tool workflow_run_resume"; bad=1; }
f=$(block "$SHEET" 'private func finish(')
grep -q 'restart: pendingRestart' <<<"$f" || { echo "$WFV: finish não repassa a escolha Retomar/Reiniciar"; bad=1; }
# Core: resume_run mantém etapa atual, histórico e contadores; só reabre execução parada.
r=$(awk '/^pub fn resume_run\(/{f=1} f{print} f&&/^}/{exit}' "$WFOPS")
[ -n "$r" ] || { echo "$WFOPS: resume_run não encontrado"; bad=1; }
grep -q 'run.current = ' <<<"$r" && { echo "$WFOPS: resume_run não pode mexer na etapa atual"; bad=1; }
grep -q 'run.history' <<<"$r" && { echo "$WFOPS: resume_run não pode mexer no histórico"; bad=1; }
finish
