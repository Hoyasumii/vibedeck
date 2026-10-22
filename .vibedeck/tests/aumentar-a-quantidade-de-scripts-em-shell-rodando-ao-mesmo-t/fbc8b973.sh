#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
for k in swift node cargo go gradle maven dotnet composer make; do has $RUN "^\s*\(?\"$k\"," "a tabela de ferramentas de build perdeu a chave $k"; done
[ "$(grep -c 'const TOOL_TABLE' $RUN)" = 1 ] || { echo "$RUN: deve haver uma única tabela de ferramentas de build"; bad=1; }
o=$(grep -rlE 'gradlew|dotnet\\s|composer\\s' crates --include=*.rs | grep -v "^$RUN$" || true)
[ -z "$o" ] || { echo "detecção de ferramentas de build duplicada fora de $RUN: $o"; bad=1; }
has $RUN 'fn build_tool_detection\(\)' "falta o teste unitário da detecção"
finish
