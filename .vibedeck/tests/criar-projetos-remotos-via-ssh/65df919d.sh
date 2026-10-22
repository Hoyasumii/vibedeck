#!/usr/bin/env bash
# 65DF919D: IA e scripts de regras aguardam pendências/conflitos; o terminal continua disponível.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/(ClaudeSession|RuleExecutionModel|WorkflowView)\.swift$|Sources/VibeDeckCore/(RuleTests|AIConversationTransport)\.swift$'
in_body $WS 'public func requireSynchronized' 'guard pendingCount == 0, conflicts\.isEmpty' "IA/regras devem exigir zero pendências e conflitos"
in_body $EXEC 'public static func configure' 'try workspace\.requireSynchronized\(\)' "lançamentos remotos (IA e regras) devem aguardar a sincronização"
in_body $EXEC 'public static func prepareContext' 'try workspace\.requireSynchronized\(\)' "envio de contexto da IA deve aguardar a sincronização"
for f in Sources/VibeDeckApp/ClaudeSession.swift Sources/VibeDeckApp/RuleExecutionModel.swift Sources/VibeDeckApp/WorkflowView.swift; do
  need $f 'RemoteWorkspace\.existing\(at: [a-z.]*root\)\?\.requireSynchronized\(\)' "a ação deve aguardar pendências e conflitos"
done
needF Sources/VibeDeckCore/RuleTests.swift 'try RemoteExecution.configure(process, root: root, command: command' "scripts de regras devem passar pela verificação de sincronização"
forbid $TERM 'requireSynchronized|RemoteExecution\.configure' "o terminal SSH não pode ser bloqueado por pendências"
run_tests remoteLaunchNeverUsesLocalBinaryAndBlocksPending workflowStateSynchronizesBeforeProviderAndStillBlocksConflicts conflictPreservesBothAcrossRestartUntilChoice
finish
