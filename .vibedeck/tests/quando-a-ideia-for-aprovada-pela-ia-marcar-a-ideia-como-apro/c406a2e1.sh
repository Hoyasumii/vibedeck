#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# C406A2E1: salvar a avaliação não promove a ideia: promotedTopic vazio e nenhum tópico criado.
require_apply
b=$(apply_body)
grep -qE 'store\.|promoteIdea|RuleTopic|createRule|addRule' <<<"$b" && bad "$LOGIC: apply só pode alterar a ideia recebida (sem tópicos/promoção)"
# Salvar avaliação no app é uma única mutateIdea; não chama promoção.
i=$(awk '/applyVerdict: \{ verdict in/{f=1} f{print} f&&/^            }$/{exit}' "$IDEAV")
[ -n "$i" ] || bad "$IDEAV: applyVerdict não encontrado"
grep -qE 'promoteIdea|unpromoteIdea|addRuleTopic|add_rule_topic' <<<"$i" && bad "$IDEAV: applyVerdict não pode promover a ideia nem criar tópicos"
has_test savedEvaluationDoesNotPromoteOrTouchRules
finish
