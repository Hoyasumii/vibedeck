#!/usr/bin/env bash
# Regras de ideia não promovida nunca entram em rules_for/checks; promover cria tópico, sincronizar não duplica,
# apagar o tópico despromove (vínculo some, approved → exploring, rascunhos ficam).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^Sources/VibeDeckCore/|^Sources/vibedeck/|^Tests/VibeDeckCoreTests/RulesTests\.swift$'
fail=0
S=Sources/VibeDeckCore/ProjectStore.swift
# applicableTopics só lê tópicos reais (rules/*.json), nunca ideias.
body=$(awk '/func applicableTopics\(/{f=1} f{print} f&&/^    }$/{exit}' "$S")
echo "$body" | grep -q 'listTopics()' || { echo "$S: applicableTopics não parte de listTopics()"; fail=1; }
echo "$body" | grep -qiE 'idea' && { echo "$S: applicableTopics consulta ideias"; fail=1; }
# rules_for (MCP/CLI) e submitCheck passam por applicableTopics.
grep -A12 'case "rules_for":' Sources/vibedeck/MCPServer.swift | grep -q 'applicableTopics(' || { echo "Sources/vibedeck/MCPServer.swift: rules_for não usa applicableTopics"; fail=1; }
grep -nE 'listIdeas\(\)|loadIdea\(' Sources/vibedeck/MCPServer.swift | while IFS=: read -r n _; do
  ctx=$(sed -n "$((n>15?n-15:1)),${n}p" Sources/vibedeck/MCPServer.swift)
  if echo "$ctx" | grep -qE 'case "(rules_for|submit_rule_check|run_rule_tests)"'; then echo "Sources/vibedeck/MCPServer.swift:$n: rules_for/check lê ideias"; exit 1; fi
done || fail=1
[ $fail -eq 0 ] || exit 1
run_tests RulesTests/ideasAndPromotion RulesTests/unpromote
