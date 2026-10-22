#!/usr/bin/env bash
# Métricas distinguem uso informado e tamanho de texto: ausente != zero, cache contado à parte, cumulativo não somado (Core Rust).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
cargo_test -p vibedeck-core --lib -- ai::usage::tests::tokens_distinguem_ausente_zero_cache_e_cumulativo ai::usage::tests::store_guarda_lista_e_limpa_sem_prompt
cargo_test -p vibedeck --test ai_cli -- uso_local_lista_e_limpa usage_record_show_install_uninstall
