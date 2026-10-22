#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $RUN 'fn concurrent_outputs_stay_separate' "falta o teste com o run_shell real"
hasF $RUN 'let handles: Vec<_> = (0..8)' "os comandos devem rodar ao mesmo tempo"
hasF $RUN 'run_shell(&format!("echo job{i}"), root, &opts(20_000))' "o teste deve usar o run_shell real"
hasF $RUN 'assert_eq!(r.output, format!("job{i}"));' "cada saída deve ser só a própria marca"
none $RUN 'RuleTestRunner::new[^\n]*concurrent' "o teste deve usar o run_shell real, não runner falso"
finish
