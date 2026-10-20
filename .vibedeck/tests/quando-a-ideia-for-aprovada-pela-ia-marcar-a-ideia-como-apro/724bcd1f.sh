#!/usr/bin/env bash
# log da gravação e da mudança de status sem conteúdo
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
f=Sources/VibeDeckApp/IdeaView.swift
grep -q '"idea.status_changed"' $f || { echo "$f: log idea.status_changed ausente"; exit 1; }
grep -q 'context: \["slug": slug, "status": idea.status.rawValue\]' $f || { echo "$f: contexto do log deve ter só slug e status"; exit 1; }
grep -q 'mutateIdea(slug, "Verificar: avaliação"' $f || { echo "$f: nome do undo da avaliação ausente"; exit 1; }
# A gravação em si é logada pelo store (caminho relativo + undo name)
grep -rq 'undoName' Sources/VibeDeckCore Sources/VibeDeckApp/ProjectModel.swift || { echo "VDLog.undoName não encontrado"; exit 1; }
