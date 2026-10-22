#!/usr/bin/env bash
# E0C84DF2: scripts de regras de projeto SSH rodam no servidor, no diretório do projeto, devolvendo saída e código.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckCore/RuleTests\.swift$'
R=Sources/VibeDeckCore/RuleTests.swift
needF $R '"VIBEDECK_ROOT": RemoteExecution.path(for: context.root)' "VIBEDECK_ROOT deve ser o diretório remoto"
needF $R 'try RemoteExecution.configure(process, root: root, command: command, environment: environment); try process.run()' "o script deve ser lançado via SSH"
B=$(body $EXEC 'public static func configure')
for p in 'connection\.inDirectory\(exports \+ body\)' 'URL\(fileURLWithPath: "/usr/bin/ssh"\)' 'connection\.commandArguments\(login\)'; do
  grep -qE -- "$p" <<<"$B" || { echo "$EXEC (configure): falta '$p'"; fail=1; }
done
needF $R 'return RuleTestOutcome(exitCode: result.status, output: result.output)' "saída e código do script devem voltar ao app"
run_tests remoteLaunchNeverUsesLocalBinaryAndBlocksPending
finish
