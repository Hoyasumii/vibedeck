#!/usr/bin/env bash
# CLI e MCP registram info (não só debug) com comando/ferramenta e ms.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/vibedeck/(CLI|MCPServer)\.swift$|^Sources/VibeDeckCore/Logging\.swift$'
fail=0
bad() { echo "$1"; fail=1; }
grep -qE 'VDLog\.info\("cli\.command_completed".*"command": commandPath\(command\).*"ms":' Sources/vibedeck/CLI.swift || bad "CLI.swift: sucesso deve gravar info cli.command_completed com command e ms"
grep -qE 'VDLog\.info\("mcp\.tool_called".*"tool": params\.name.*"ms":' Sources/vibedeck/MCPServer.swift || bad "MCPServer.swift: sucesso deve gravar info mcp.tool_called com tool e ms"
grep -q 'VDLog.configure(component: .cli' Sources/vibedeck/CLI.swift || bad "CLI.swift: component .cli não configurado"
grep -q 'VDLog.configure(component: .mcp' Sources/vibedeck/MCPServer.swift || bad "MCPServer.swift: component .mcp não configurado"
grep -q 'VDLog.flush()' Sources/vibedeck/CLI.swift || bad "CLI.swift: flush antes de sair é necessário para a entrada chegar ao disco"
[ $fail -eq 0 ] || exit 1
