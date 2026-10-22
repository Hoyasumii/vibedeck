#!/usr/bin/env bash
# Otimizações de contexto têm testes de integridade e economia: guia menor sem perda, paginação, resumo de check, contrato/orçamento do MCP.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
cargo_test -p vibedeck-core --lib -- ai::guide::tests::guia_reduz_contexto_sem_perder_documentacao ai::guide::tests::politica_compartilhada_aparece_uma_vez ai::context::tests::paginas_sem_perda_e_confinadas
cargo_test -p vibedeck --test rules_mcp -- rules_for_compact_output_and_scripts
cargo_test -p vibedeck --test ai_cli -- tools_de_ia_no_tools_list
# Contrato (compatível para trás) e orçamento (catálogo de tools <= 70% da baseline, instruções <= 1200) do MCP Rust.
cargo build -q --release -p vibedeck
python3 -I scripts/mcp-contract.py target/release/vibedeck check Tests/Fixtures
