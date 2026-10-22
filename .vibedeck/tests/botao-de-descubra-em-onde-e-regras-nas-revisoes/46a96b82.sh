#!/usr/bin/env bash
set -euo pipefail
# O Descubra nunca grava direto: mostra uma proposta e o usuário aceita (tudo ou por campo);
# cada aceite é um único passo de undo.
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckApp/ProjectModel\.swift$'
# A lógica e o runner não gravam nada: nada de store/AtomicFile/write/save.
forbid "$CORE" 'AtomicFile|\.write\(|\bsave[A-Z(]|store\.(save|write|update|mutate)|saveRecord' "ReviewDiscover (lógica) não pode gravar; só monta a proposta"
forbid "$APP" 'AtomicFile|\.write\(to|\bsave[A-Z(]|store\.(save|write|update|mutate)|saveRecord|mutate(Item|Group)?\(|\.apply\(' "o runner/sheet do Descubra não pode gravar nem aplicar a proposta sozinho"
forbid_rs 'save_review|write_atomic|std::fs::write|store\.save' "ReviewDiscover (Core Rust) não pode gravar; só monta a proposta"
# O runner só chega a .ready com uma proposta validada.
need "$APP" 'state = \.ready\(ReviewDiscover\.proposal\(' "o resultado do Descubra precisa virar proposta (state = .ready(ReviewDiscover.proposal(…)))"
# A sheet aplica só no botão de aceite, com os campos/tópicos marcados.
need "$APP" 'LoggedButton\("Aplicar selecionados"\)' "a sheet precisa de um botão de aceite explícito"
sheet=$(body "$APP" 'struct ReviewDiscoverSheet')
[ "$(printf '%s\n' "$sheet" | grep -cE '\bapply\(')" -eq 1 ] || { echo "$APP: ReviewDiscoverSheet deve chamar apply exatamente uma vez (no botão Aplicar selecionados)"; fail=1; }
printf '%s\n' "$sheet" | grep -A2 'LoggedButton("Aplicar selecionados")' | grep -q 'apply(fields, topics)' || { echo "$APP: Aplicar selecionados deve chamar apply(fields, topics)"; fail=1; }
# Na view, a proposta é aplicada uma única vez, dentro de um único mutate (um passo de undo).
n=$(grep -cE 'proposal\.apply\(' "$VIEW" || true)
[ "$n" -eq 1 ] || { echo "$VIEW: proposal.apply deve aparecer exatamente uma vez (achei $n)"; fail=1; }
grep -nE 'proposal\.apply\(' "$VIEW" | grep -qE 'mutate\("[^"]+"\) \{ proposal\.apply\(' || { echo "$VIEW: proposal.apply precisa estar dentro de um único mutate(\"…\") { … } (um passo de undo)"; fail=1; }
need "$VIEW" 'model\.mutateItem\(slug, item\.id, action, undo: undo' "o mutate do inspetor deve ir para model.mutateItem com o undo manager"
grep -A16 'func mutateGroup(' Sources/VibeDeckApp/ProjectModel.swift | grep -q 'registerUndo' || { echo "Sources/VibeDeckApp/ProjectModel.swift: mutateGroup não registra undo"; fail=1; }
rtest substituir_exige_opt_in_e_topicos_so_somam
finish
