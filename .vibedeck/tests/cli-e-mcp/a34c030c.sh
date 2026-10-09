#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -q "^Sources/vibedeck/"; then exit 77; fi
MCP=Sources/vibedeck/MCPServer.swift; CLI=Sources/vibedeck/CLI.swift
fail() { echo "$1" >&2; exit 1; }
chk() { grep -qF -- "$2" "$MCP" || fail "$MCP: texto obrigatório ausente: $2"; }
chk x "REGRA OBRIGATÓRIA: nenhuma tarefa neste projeto está concluída sem passar pelas regras"
chk x "chame rules_for com os arquivos que você alterou"
chk x "chame submit_rule_check respondendo pass/fail/na para TODAS as regras manuais"
chk x "se passed=false, corrija e envie outro check"
chk x "OBRIGATÓRIO antes de concluir uma tarefa"
chk x "Responda TODAS as regras de rules_for"
