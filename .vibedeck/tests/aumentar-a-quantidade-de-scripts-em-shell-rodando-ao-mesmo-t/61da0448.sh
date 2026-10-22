#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $RUN 'fn concurrent_outputs_stay_separate' "falta o teste com execuções simultâneas do shell real"
hasF $RUN 'assert_eq!(r.output, format!("job{i}"));' "cada saída deve conter só a própria marca"
hasF $RUN 'let buffer: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));' "cada execução deve ter o próprio buffer de saída"
hasF $RUN 'make_pipe().and_then' "cada execução deve criar o próprio pipe"
none $RUN 'static [A-Z_]+: *(Mutex<Vec<u8>>|Arc<Mutex<Vec<u8>>>)' "o buffer de saída não pode ser compartilhado entre execuções"
finish
