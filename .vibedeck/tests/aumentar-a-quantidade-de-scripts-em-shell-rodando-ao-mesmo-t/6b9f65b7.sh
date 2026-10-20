#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $MODEL 'if error == nil, !cancelled,' "finish não pode gravar duração após cancelamento ou erro"
hasF $APPT "cancelled scripts don't record durations" "falta o teste de timings após cancelar"
hasF $APPT 'UserDefaults.standard.data(forKey: key) == nil' "o teste deve exigir que nada seja gravado"
finish
