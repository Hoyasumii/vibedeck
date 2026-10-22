#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $EXEC 'on_event(RuleScriptEvent::Started {' "run_scripts não emite Started"
hasF $EXEC 'on_event(RuleScriptEvent::Finished {' "run_scripts não emite Finished"
before $EXEC 'on_event\(RuleScriptEvent::Started' 'on_event\(RuleScriptEvent::Finished' "Started deve ser emitido antes do Finished"
hasF $EXEC 'assert_eq!(events.len(), 12);' "o teste deve exigir exatamente um Started e um Finished por regra"
hasF $EXEC 'assert!(s < f);' "o teste deve exigir Started antes de Finished"
finish
