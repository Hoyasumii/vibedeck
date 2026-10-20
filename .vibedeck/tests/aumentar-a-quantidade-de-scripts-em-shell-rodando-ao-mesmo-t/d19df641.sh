#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'BuildToolLock.keys(command: $0, root: root)' "runScripts deve detectar a ferramenta lendo o arquivo do script"
hasF $RT 'public static func keys(command: String, root: URL) -> [String]' "falta a detecção que lê o arquivo do script"
hasF $RT 'try? String(contentsOf: url, encoding: .utf8)' "a detecção deve ler o conteúdo do arquivo"
hasF $RE 'bash .vibedeck/tests/x/a.sh' "falta o teste com wrapper a.sh"
hasF $RE 'bash .vibedeck/tests/x/b.sh' "falta o teste com wrapper b.sh"
hasF $RE '!peak.overlap("bash .vibedeck/tests/x/a.sh", "bash .vibedeck/tests/x/b.sh")' "o teste deve exigir serialização dos wrappers"
finish
