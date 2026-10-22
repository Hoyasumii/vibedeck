#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# E0C84DF2: scripts de regras de um projeto remoto executam no servidor, no diretório do projeto, devolvendo saída e código.
# O app chama `run_rule_tests` no Core, que roda no servidor (MCP por SSH); o runner Rust executa na raiz do projeto.
R=crates/vibedeck-core/src/rules/runner.rs
X=crates/vibedeck-core/src/rules/execution.rs
need Sources/VibeDeckApp/RuleExecutionModel.swift 'store\.call\("run_rule_tests"' "o app deve rodar os scripts via Core (run_rule_tests)"
in_body $CSTORE 'static func sshLocation' 'launcher\("vibedeck", arguments: \["mcp",[^]]*"-C", workspace\.destination\.directory\]' "o Core remoto deve abrir a pasta do projeto no servidor"
need $R '\.current_dir\(root\)' "o script deve rodar com o diretório do projeto como diretório de trabalho"
need $X '"VIBEDECK_ROOT"\.into\(\), ctx\.root\.display\(\)\.to_string\(\)' "VIBEDECK_ROOT deve ser a raiz do projeto (no servidor)"
need $R 'stdout\+stderr|merged|stderr' "a saída (stdout+stderr) deve voltar ao app"
need $R 'exit_code|status\.code\(\)|code\(\)' "o código de saída do script deve voltar ao app"
# Scripts de regras do app que ainda lançam processo local passam por RemoteExecution.configure.
need Sources/VibeDeckApp/Core/Model/RuleTests.swift 'try RemoteExecution\.configure\(process, root: root, command: command' "shell local do app deve passar por RemoteExecution.configure"
B=$(body $EXEC 'static func configure')
for p in 'connection\.inDirectory\(exports \+ body\)' 'URL\(fileURLWithPath: "/usr/bin/ssh"\)' 'connection\.commandArguments\(login\)'; do
  grep -qE -- "$p" <<<"$B" || { echo "$EXEC (configure): falta '$p'"; fail=1; }
done
finish
