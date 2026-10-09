#!/usr/bin/env bash
set -euo pipefail
cd "${VIBEDECK_ROOT:-.}"
if [ -n "${VIBEDECK_FILES:-}" ] && ! printf "%s\n" "$VIBEDECK_FILES" | grep -q "^Sources/vibedeck/"; then exit 77; fi
MCP=Sources/vibedeck/MCPServer.swift; CLI=Sources/vibedeck/CLI.swift
fail() { echo "$1" >&2; exit 1; }
chk() { grep -qF -- "$2" "$MCP" || fail "$MCP: texto obrigatório ausente: $2"; }
chk x "REGRA OBRIGATÓRIA: nenhuma tarefa neste projeto está concluída sem passar pelas regras"
chk x "chame rules_for com os arquivos que você alterou"
chk x "chame submit_rule_check (results=[]): ele roda os scripts das regras sozinho"
chk x "verify_manual=true respondendo pass/fail/na para TODAS"
chk x "se passed=false, corrija e envie outro check"
chk x "OBRIGATÓRIO antes de concluir uma tarefa"
chk x "Com verify_manual=true, responda TODAS as manuais em results"
