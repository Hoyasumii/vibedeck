#!/usr/bin/env bash
set -euo pipefail
# A chamada ao Claude do Descubra roda só com ferramentas de leitura (Read/Grep/Glob), sem Edit/Write/Bash.
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckApp/Core/AI/(AIReadOnlyProcess|CodexReadOnly)\.swift$'
need "$CORE" 'static let tools = \["Read", "Grep", "Glob"\]$' "ReviewDiscover.tools deve ser exatamente [\"Read\", \"Grep\", \"Glob\"]"
need "$RS" 'pub const TOOLS: \[&str; 3\] = \["Read", "Grep", "Glob"\];' "TOOLS (Core Rust) deve ser exatamente [\"Read\", \"Grep\", \"Glob\"]"
forbid "$CORE" '"(Edit|Write|Bash|MultiEdit|NotebookEdit|WebFetch|WebSearch|Task)"' "ferramenta não permitida no Descubra"
forbid_rs '"(Edit|Write|Bash|MultiEdit|NotebookEdit|WebFetch|WebSearch|Task)"' "ferramenta não permitida no Descubra"
forbid "$CORE" 'dangerously|bypassPermissions|--permission-mode|--add-dir|--mcp-config ' "argumento que amplia permissões no Descubra"
forbid_rs 'dangerously|bypassPermissions|--permission-mode|--add-dir|--mcp-config' "argumento que amplia permissões no Descubra"
args=$(body "$CORE" 'static func arguments\(')
for a in '"--tools", tools' '"--allowedTools", tools' '"--strict-mcp-config"'; do
  printf '%s\n' "$args" | grep -qF -- "$a" || { echo "$CORE: arguments() sem $a"; fail=1; }
done
rargs=$(body "$RS" '^pub fn arguments\(')
for a in '"--tools"' '"--allowedTools"' '"--strict-mcp-config"'; do
  printf '%s\n' "$rargs" | grep -qF -- "$a" || { echo "$RS: arguments() sem $a"; fail=1; }
done
# Os processos do Claude usam exatamente esses argumentos.
for f in "$APP" Sources/VibeDeckApp/Core/AI/AIReadOnlyProcess.swift; do
  need "$f" 'process\.arguments = ReviewDiscover\.arguments\(\)$' "o runner deve lançar o claude com ReviewDiscover.arguments()"
  forbid "$f" 'process\.arguments *(\+=|\.append)\(?[^m]*"--(allowedTools|tools|permission-mode|add-dir|mcp-config)' "o runner não pode ampliar as ferramentas do claude"
done
# Caminho Codex: sandbox somente leitura (sem escrita no workspace) e sem aprovações.
need "$OPERATION" 'workspaceWrites: false' "Codex do Descubra deve rodar sem escrita no workspace"
C=Sources/VibeDeckApp/Core/AI/CodexReadOnly.swift
need "$C" '\.string\(workspaceWrites \? "workspace-write" : "read-only"\)' "Codex do Descubra precisa de sandbox read-only quando workspaceWrites == false"
need "$C" '"approvalPolicy": \.string\("never"\)' "Codex do Descubra precisa de approvalPolicy never"
rtest argumentos_somente_leitura
finish
