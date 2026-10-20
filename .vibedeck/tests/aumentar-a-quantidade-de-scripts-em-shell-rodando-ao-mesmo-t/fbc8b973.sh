#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
for k in swift node cargo go gradle maven dotnet composer make; do hasF $RT "(\"$k\", #\"" "a tabela de ferramentas de build perdeu a chave $k"; done
[ "$(grep -c 'static let table' $RT)" = 1 ] || { echo "$RT: deve haver uma única tabela de ferramentas de build"; bad=1; }
o=$(grep -rlE 'gradlew|dotnet\\s|composer\\s' Sources | grep -v "^$RT$" || true)
[ -z "$o" ] || { echo "detecção de ferramentas de build duplicada fora do Core: $o"; bad=1; }
has $RTT 'func buildToolDetectionCoversEcosystems' "falta o teste unitário da detecção"
finish
