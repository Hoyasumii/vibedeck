#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'on_event: &(dyn Fn(RuleScriptEvent) + Sync),' "on_event deve ser Fn + Sync"
before $EXEC 'let mut guard = lock\(&shared\);' 'on_event\(RuleScriptEvent::Started' "o Started deve ser entregue pelo laço (com o lock do estado)"
before $EXEC 'let mut g = lock\(&shared\);' 'on_event\(RuleScriptEvent::Finished' "o Finished deve ser entregue com o lock do estado tomado"
finish
