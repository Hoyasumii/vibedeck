#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
has $RTT 'func concurrentShellOutputsStaySeparate' "falta o teste com o ShellRunner real"
hasF $RTT 'concurrentPerform(iterations: 2)' "os dois comandos devem rodar ao mesmo tempo"
hasF $RTT 'echo \(mark); sleep 1; echo \(mark)' "os comandos devem dormir 1 s"
hasF $RTT '"A\nA"' "a saída A deve ser só A"
hasF $RTT '"B\nB"' "a saída B deve ser só B"
none $RTT 'RuleTestRunner[^\n]*concurrentPerform' "o teste deve usar o ShellRunner real, não runner falso"
finish
