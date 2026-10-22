#!/usr/bin/env bash
# D12CD479: o terminal de projeto SSH abre ssh -tt no servidor, iniciando no diretório remoto.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
B=$(body $TERM 'func start\(\)')
grep -qF 'if let workspace = RemoteWorkspace.existing(at: root)' <<<"$B" || { echo "$TERM: o terminal deve detectar projeto SSH"; fail=1; }
grep -qF 'connection.inDirectory("exec \"${SHELL:-/bin/sh}\" -l")' <<<"$B" || { echo "$TERM: o shell remoto deve começar no diretório do projeto"; fail=1; }
grep -qF 'executable: "/usr/bin/ssh", args: connection.commandArguments(command, terminal: true)' <<<"$B" || { echo "$TERM: o terminal deve rodar via ssh com pty"; fail=1; }
needF $CONN 'public func inDirectory(_ command: String) -> String { "cd " + Self.quote(destination.directory)' "o diretório remoto deve ser o do projeto"
run_tests connectionArgumentsUsePortUserAliasAndStrictHostKeys
finish
