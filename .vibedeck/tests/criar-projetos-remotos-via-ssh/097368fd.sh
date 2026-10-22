#!/usr/bin/env bash
# 097368FD: ferramenta ausente no servidor gera erro que a identifica (exit 127), sem lançar o executável do Mac.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $EXEC 'Ferramenta remota ausente: \(name).' "a mensagem deve identificar a ferramenta ausente"
needF $EXEC '>&2; exit 127; }; exec ' "a ausência deve encerrar com erro antes de executar"
B=$(body $EXEC 'static func configure')
grep -qF 'process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")' <<<"$B" || { echo "$EXEC: projeto remoto deve trocar sempre o executável local por ssh"; fail=1; }
grep -qE 'catch|try\?' <<<"$B" && { echo "$EXEC (configure): erros não podem cair em execução local"; fail=1; }
finish
