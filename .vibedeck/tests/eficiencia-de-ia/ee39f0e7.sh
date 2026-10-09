#!/usr/bin/env bash
# Política cobre todos os provedores; sem troca/rebaixamento automático de modelo; limitações reportadas.
set -euo pipefail
fail=0
f=Sources/VibeDeckCore/AIPromptPolicy.swift
for p in 'Não troque modelo nem provedor automaticamente' 'informe' 'sugira um modelo mais capaz'; do
    grep -qF "$p" "$f" || { echo "$f: cláusula ausente: $p"; fail=1; }
done
if grep -rnE 'fallback-model|fallbackModel|downgrade' Sources --include=*.swift; then
    echo "Troca/rebaixamento automático de modelo encontrado"; fail=1
fi
grep -q 'incomplete' Sources/VibeDeckApp/AIReadOnlyOperation.swift || { echo "AIReadOnlyOperation não reporta limitação (incomplete)"; fail=1; }
for g in Sources/VibeDeckCore/CodexReadOnly.swift Sources/VibeDeckCore/ClaudeStream.swift; do
    grep -q 'AIPromptPolicy' "$g" || { echo "$g: provedor sem política compartilhada"; fail=1; }
done
exit $fail
