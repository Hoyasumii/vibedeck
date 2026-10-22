#!/usr/bin/env bash
# 24CEB689: projeto SSH usa o provedor do servidor; não exige o provedor instalado no Mac.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckCore/AIProvider\.swift$'
needF $EXEC 'RemoteWorkspace.existing(at: root) != nil || provider.isInstalled' "provedor remoto não pode exigir instalação local"
needF $EXEC 'RemoteWorkspace.existing(at: root) == nil ? AIProvider.installed : AIProvider.allCases' "projeto SSH deve oferecer os provedores do servidor"
needF $EXEC 'RemoteWorkspace.existing(at: root) == nil ? provider.executable : URL(fileURLWithPath: "/" + provider.rawValue)' "projeto SSH não pode usar o executável local do provedor"
needF Sources/VibeDeckCore/AIProvider.swift 'return RemoteExecution.providers(root: root)' "a lista de provedores deve considerar o projeto SSH"
run_tests remoteProjectsUseServerProviders remoteLaunchNeverUsesLocalBinaryAndBlocksPending
finish
