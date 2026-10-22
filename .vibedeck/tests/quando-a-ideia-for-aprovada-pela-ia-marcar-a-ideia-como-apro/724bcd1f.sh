#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 724BCD1F (should): salvar a avaliação registra no log a ação e a mudança de status, sem conteúdo da ideia.
grep -q '"idea.status_changed"' "$IDEAV" || bad "$IDEAV: log idea.status_changed ausente"
grep -q 'context: \["slug": slug, "status": idea.status.rawValue\]' "$IDEAV" || bad "$IDEAV: contexto do log deve ter só slug e status"
grep -q 'mutateIdea(slug, "Verificar: avaliação"' "$IDEAV" || bad "$IDEAV: nome do undo da avaliação ausente"
# A gravação em si é logada pelo store (caminho relativo + undo name).
grep -rq 'undoName' Sources/VibeDeckApp/Core/Support/Logging.swift || bad "VDLog.undoName não encontrado"
finish
