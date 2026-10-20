#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
for f in README.md .vibedeck/guide.md; do
  grep -qi 'paralelo' $f || { echo "$f: não documenta a execução paralela"; bad=1; }
  grep -qi 'ferramenta de build' $f || { echo "$f: não documenta a serialização por ferramenta de build"; bad=1; }
  grep -qi 'Configurações' $f || { echo "$f: não documenta a configuração do limite nas Configurações do app"; bad=1; }
done
finish
