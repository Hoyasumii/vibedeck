#!/usr/bin/env bash
# A83A6E65 (D16): reconexão automática com intervalo crescente (RemoteLink/RemoteBackoff), botão Reconectar; senha só por ação do usuário.
# Análise estática; o comportamento é coberto por CoreModelsTests.reconnectBackoffGrowsUpToSixtySeconds (swift test, só no macOS).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
needF $LINK 'enum RemoteBackoff' "falta RemoteBackoff (intervalos da reconexão)"
in_body $LINK 'static func delay\(attempt' 'value \*= 2' "o intervalo deve crescer (dobrar a cada tentativa)"
in_body $LINK 'static func delay\(attempt' 'min\(value, maximum\)' "o intervalo deve ter teto"
need $LINK 'static let maximum: TimeInterval = 60' "o teto do intervalo deve ser 60 s"
needF $LINK 'final class RemoteLink' "falta RemoteLink (estado da conexão SSH)"
in_body $LINK 'private func lose\(' 'scheduleNext\(\)' "ao perder a conexão deve agendar a próxima tentativa"
in_body $LINK 'private func scheduleNext\(' 'RemoteBackoff\.delay\(attempt: attempt\)' "o agendamento deve usar RemoteBackoff"
in_body $LINK 'private func connect\(' 'attempt \+= 1' "cada falha de reconexão deve aumentar a tentativa (intervalo crescente)"
in_body $LINK 'private func connect\(' 'attempt = 0' "reconectar com sucesso deve zerar a tentativa"
in_body $LINK 'func reconnectNow\(' 'forceNow = true' "Reconectar deve tentar já, sem esperar o intervalo"
# A reconexão automática só usa a senha já guardada no Chaves ou digitada pelo usuário; nunca pede por conta própria.
in_body $LINK 'private func connect\(' 'SSHCredentials\.password\(for: destination\)' "a reconexão deve usar só a senha guardada ou digitada pelo usuário"
needF $STATUS 'LoggedButton("Reconectar") { link.reconnectNow() }' "falta o botão Reconectar no estado SSH"
needF $STATUS 'LoggedButton("Senha…") { link.credentials = true }' "a senha deve ser pedida por ação do usuário (botão Senha…)"
needF $CTESTS 'func reconnectBackoffGrowsUpToSixtySeconds' "falta o teste do intervalo crescente"
finish
