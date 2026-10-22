#!/usr/bin/env bash
# Contexto sob demanda: guia curto, catálogo paginado e referências recuperáveis sem perda (Core Rust).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
cargo_test -p vibedeck-core --lib -- ai::context::tests::paginas_sem_perda_e_confinadas ai::guide::tests::indice_e_secoes
cargo_test -p vibedeck-core --test ai_items -- catalogo_pagina_sem_enviar_prompts_do_usuario
cargo_test -p vibedeck --test ai_cli -- guide_indice_secao_e_json catalogo_cli_e_mcp contexto_pagina_sem_perder_o_resto
