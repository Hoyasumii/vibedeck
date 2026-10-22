#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'BuildToolLock::keys_for_command(&command, root)' "run_scripts deve detectar a ferramenta lendo o arquivo do script"
hasF $RUN 'pub fn keys_for_command(command: &str, root: &Path) -> Vec<&'"'"'static str> {' "falta a detecção que lê o arquivo do script"
hasF $RUN 'std::fs::read_to_string(&url)' "a detecção deve ler o conteúdo do arquivo"
has $RUN 'fn build_tool_detection_follows_wrappers_without_looping' "falta o teste com wrappers"
hasF $RUN 'BuildToolLock::keys_for_command("t/a.sh", root), ["cargo"]' "o teste deve exigir a chave do build chamado dentro do wrapper"
finish
