#!/usr/bin/env bash
# A chamada ao Claude do Descubra roda só com ferramentas de leitura (Read/Grep/Glob), sem Edit/Write/Bash.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckCore/CodexReadOnly\.swift$'
need "$CORE" 'public static let tools = \["Read", "Grep", "Glob"\]$' "ReviewDiscover.tools deve ser exatamente [\"Read\", \"Grep\", \"Glob\"]"
forbid "$CORE" '"(Edit|Write|Bash|MultiEdit|NotebookEdit|WebFetch|WebSearch|Task)"' "ferramenta não permitida no Descubra"
forbid "$CORE" 'dangerously|bypassPermissions|--permission-mode|--add-dir|--mcp-config ' "argumento que amplia permissões no Descubra"
args=$(body "$CORE" 'public static func arguments\(')
for a in '"--tools", tools' '"--allowedTools", tools' '"--strict-mcp-config"'; do
  printf '%s\n' "$args" | grep -qF -- "$a" || { echo "$CORE: arguments() sem $a"; fail=1; }
done
# O processo do Claude usa exatamente esses argumentos.
need "$APP" 'process\.arguments = ReviewDiscover\.arguments\(\)$' "o runner deve lançar o claude com ReviewDiscover.arguments()"
forbid "$APP" 'process\.arguments *(\+=|\.append)' "o runner não pode acrescentar argumentos ao claude"
# Caminho Codex: sandbox somente leitura, sem aprovações.
if grep -q 'CodexReadOnly()' "$APP"; then
  C=Sources/VibeDeckCore/CodexReadOnly.swift
  need "$C" '"sandbox": \.string\("read-only"\)' "Codex do Descubra precisa de sandbox read-only"
  need "$C" '"approvalPolicy": \.string\("never"\)' "Codex do Descubra precisa de approvalPolicy never"
fi
finish
run_tests ReviewDiscoverTests/argumentsAreReadOnly
