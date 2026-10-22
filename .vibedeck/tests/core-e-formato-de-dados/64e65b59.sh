#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# verification_problems / ensure_verified: item com regras só vai para done com o check mais recente aprovado.
applies '(^|/)(crates/vibedeck-core/(src|tests)/|Tests/)'
grep -q "Regra nova desde o último check" crates/vibedeck-core/src/rules/tasks.rs || { echo "crates/vibedeck-core/src/rules/tasks.rs: mensagem 'Regra nova desde o último check' mudou"; exit 1; }
grep -q "pub fn ensure_verified" crates/vibedeck-core/src/rules/tasks.rs || { echo "crates/vibedeck-core/src/rules/tasks.rs: ensure_verified sumiu"; exit 1; }
grep -q "ensure_verified" crates/vibedeck-core/src/reviews/gate.rs || { echo "crates/vibedeck-core/src/reviews/gate.rs: o gate não chama ensure_verified"; exit 1; }
cargo_tests vibedeck-core gate_item_livre_sem_regras gate_por_paths_do_topico gate_regra_nova_e_manual_must gate_regras_explicitas_do_item update_com_regras_grava_antes_do_gate
