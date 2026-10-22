#!/usr/bin/env bash
# O formato novo (action/control/label) tem teste: codificação, decodificação tolerante e filtro por ação (Core Rust).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^crates/vibedeck-core/src/project/logs\.rs$'
grep -q 'fn filtro_de_acao_e_leitura_antiga' "$RUSTLOG" || { echo "$RUSTLOG: teste de filtro por ação / leitura de entradas antigas ausente"; exit 1; }
grep -q 'fn linhas_corrompidas_e_fracao_de_segundos' "$RUSTLOG" || { echo "$RUSTLOG: teste de decodificação tolerante ausente"; exit 1; }
tests=$(awk '/#\[test\]/ {getline; sub(/^ *fn /, ""); sub(/\(.*/, ""); print}' "$RUSTLOG")
# shellcheck disable=SC2086
run_tests $tests
