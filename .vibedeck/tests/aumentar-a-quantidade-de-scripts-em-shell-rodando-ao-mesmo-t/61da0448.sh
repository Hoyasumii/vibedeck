#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $RTT 'func concurrentShellOutputsStaySeparate' "falta o teste com dois ShellRunner simultâneos"
hasF $RTT '== "A\nA"' "a saída A deve conter só a própria marca"
hasF $RTT '== "B\nB"' "a saída B deve conter só a própria marca"
hasF $RTT 'concurrentPerform(iterations: 2)' "o teste deve rodar os dois comandos ao mesmo tempo"
hasF $RT 'let pipe = Pipe()' "cada execução deve ter o próprio Pipe"
none $RT 'static (var|let) .*Pipe' "o Pipe não pode ser compartilhado entre execuções"
finish
