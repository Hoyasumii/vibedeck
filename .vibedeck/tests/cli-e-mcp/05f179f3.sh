#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -q "^Sources/vibedeck/"; then exit 77; fi
MCP=Sources/vibedeck/MCPServer.swift; CLI=Sources/vibedeck/CLI.swift
fail() { echo "$1" >&2; exit 1; }
sed -n "/^func vibedeckExecutablePath/,/^}/p" "$MCP" > /tmp/vd_exec_$$.txt
trap "rm -f /tmp/vd_exec_$$.txt" EXIT
for p in "ProcessInfo.processInfo.environment\[\"PATH\"\]" "isExecutableFile(atPath: candidate)" "Bundle.main.executablePath"; do
  grep -q "$p" /tmp/vd_exec_$$.txt || fail "$MCP: vibedeckExecutablePath perdeu: $p"
done
# PATH vem antes do binário atual
a=$(grep -n "environment\[\"PATH\"\]" /tmp/vd_exec_$$.txt | head -1 | cut -d: -f1); b=$(grep -n "Bundle.main.executablePath" /tmp/vd_exec_$$.txt | head -1 | cut -d: -f1)
[ "$a" -lt "$b" ] || fail "$MCP: o binário atual deve ser só o fallback, depois do PATH"
grep -qF "scope == .project ? \"vibedeck\" : vibedeckExecutablePath()" "$MCP" || fail "$MCP: escopo project deve registrar o comando \"vibedeck\" do PATH, não caminho absoluto"
