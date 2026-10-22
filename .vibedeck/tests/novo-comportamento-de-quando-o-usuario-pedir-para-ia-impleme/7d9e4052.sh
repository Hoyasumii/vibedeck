#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# Reiniciar começa pela etapa inicial do workflow
hasF "$SHEET" 'LoggedButton("Reiniciar") { confirm(restart: true) }' "Reiniciar deve confirmar com restart: true"
i=$(block "$MODEL" 'func prepareIdeaImplementation(')
grep -q 'restart' <<<"$i" || { echo "$MODEL: prepareIdeaImplementation ignora restart"; bad=1; }
# O app reinicia pela tool workflow_run_restart (CoreStore.restartRun), que roda restart_from_beginning no Core:
# mesma execução, novo ciclo, a partir da primeira etapa.
grep -q 'if restart { run = try await store.restartRun(existing.slug) }' <<<"$i" || { echo "$MODEL: Reiniciar deve usar store.restartRun(existing.slug)"; bad=1; }
CR=Sources/VibeDeckApp/Core/CoreStore+Runs.swift
r2=$(block "$CR" 'func restartRun(')
grep -q '"workflow_run_restart"' <<<"$r2" || { echo "$CR: restartRun deve usar a tool workflow_run_restart"; bad=1; }
grep -q 'restart_from_beginning(&mut run, &flow)' crates/vibedeck-core/src/app.rs || { echo "crates/vibedeck-core/src/app.rs: run_restart não usa restart_from_beginning"; bad=1; }
grep -q '"workflow_run_restart"' crates/vibedeck/src/mcp/tools/app.rs || { echo "crates/vibedeck/src/mcp/tools/app.rs: tool workflow_run_restart sumiu"; bad=1; }
r=$(awk '/^pub fn restart_from_beginning\(/{f=1} f{print} f&&/^}/{exit}' "$WFENGINE")
grep -q 'workflow.steps.first()' <<<"$r" || { echo "$WFENGINE: restart_from_beginning não usa a primeira etapa"; bad=1; }
grep -q 'run.current = Some(first)' <<<"$r" || { echo "$WFENGINE: restart_from_beginning não move a etapa atual para a inicial"; bad=1; }
finish
