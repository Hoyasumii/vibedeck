#!/usr/bin/env bash
set -euo pipefail
# Executa contratos do tópico e testes Swift atuais, sem rede (limite interno de 110s).
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/_check.py" 2ce9184c
