#!/usr/bin/env bash
# CLI e MCP (Rust) registram info (não só debug) com comando/ferramenta e ms.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^crates/vibedeck(-core)?/src/(cli/|mcp/|main\.rs|project/logs\.rs)'
fail=0
bad() { echo "$1"; fail=1; }
src() { grep -rn --include='*.rs' "$@" crates/vibedeck/src || true; }
src 'logs::info("cli.command_completed"\|info("cli.command_completed"' | grep -q . || bad "crates/vibedeck/src: sucesso do CLI deve gravar info cli.command_completed com command e ms (logs::info nunca é chamado)"
! src 'cli.command_completed' | grep -q . || src 'cli.command_completed' | grep -q '"ms"' || bad "crates/vibedeck/src: cli.command_completed sem context ms"
src 'mcp.tool_called' | grep -q . || bad "crates/vibedeck/src/mcp: sucesso de tools/call deve gravar info mcp.tool_called com tool e ms"
! src 'mcp.tool_called' | grep -q . || src 'mcp.tool_called' | grep -q '"tool"' || bad "crates/vibedeck/src/mcp: mcp.tool_called sem context tool"
src 'configure(.*LogComponent::Cli' | grep -q . || bad "crates/vibedeck/src: logs::configure(LogComponent::Cli, ...) não é chamado"
src 'configure(.*LogComponent::Mcp' | grep -q . || bad "crates/vibedeck/src: logs::configure(LogComponent::Mcp, ...) não é chamado"
[ $fail -eq 0 ] || exit 1
