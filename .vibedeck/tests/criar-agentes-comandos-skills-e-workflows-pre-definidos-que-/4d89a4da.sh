#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 4D89A4DA: adicionar do catálogo nunca sobrescreve nem apaga item existente; slug em uso recebe sufixo (slug::make + slug::unique).
need "$PERSONA" 'store\.new_slug::<P>\(&title' "persona::create deve gerar slug novo"
need crates/vibedeck-core/src/store.rs 'slug::make\(title\)' "new_slug deve derivar o slug do título (slug::make)"
need crates/vibedeck-core/src/store.rs 'slug::unique\(&base, &dir, "json"\)' "new_slug deve evitar colisão (slug::unique)"
need "$KITS" 'slug::unique\(&slug::make\(title\)' "workflow do kit deve usar slug::make + slug::unique"
# delete_installed só remove o que esta própria operação criou (rollback).
grep -qF 'for item in created.iter().rev()' "$KITS" || { echo "$KITS: o rollback deve apagar só o que foi criado nesta operação"; fail=1; }
n=$(grep -cE 'delete_(agent|command|skill|workflow)' "$KITS" || true)
[ "$n" -eq 4 ] || { echo "$KITS: delete_* deve aparecer só no rollback (delete_installed); achei $n usos"; fail=1; }
# Comportamento: adicionar duas vezes cria "-2" e preserva o conteúdo anterior.
BIN=${VIBEDECK_BIN:-target/debug/vibedeck}
if [ -x "$BIN" ]; then
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  ( cd "$T" && "$OLDPWD/$BIN" init --name T . >/dev/null 2>&1 && "$OLDPWD/$BIN" kits add manutencao:agent >/dev/null 2>&1 \
    && before=$(cat .vibedeck/agents/revisor-de-manutencao.json) \
    && "$OLDPWD/$BIN" kits add manutencao:agent >/dev/null 2>&1 \
    && [ -f .vibedeck/agents/revisor-de-manutencao-2.json ] && [ "$before" = "$(cat .vibedeck/agents/revisor-de-manutencao.json)" ] ) \
    || { echo "kits add repetido deve criar slug -2 e preservar o item existente"; fail=1; }
fi
finish
