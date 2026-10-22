#!/usr/bin/env bash
# 48989EAC: os provedores de IA de projeto SSH rodam no servidor via ssh, no diretório remoto.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckCore/(AIConversationTransport|CodexRPC|AIReadOnlyProcess|CodexReadOnly|CodexReadTools)\.swift$'
C=Sources/VibeDeckCore
needF $C/AIConversationTransport.swift 'try RemoteExecution.configure(p, root: configuration.root, program: "claude")' "Claude deve rodar no servidor"
needF $C/CodexRPC.swift 'try RemoteExecution.configure(p, root: root, program: "codex")' "Codex deve rodar no servidor"
needF $C/AIReadOnlyProcess.swift 'try RemoteExecution.configure(process, root: root, program: "claude")' "consultas de leitura devem rodar no servidor"
needF $C/CodexRPC.swift '"cwd": .string(RemoteExecution.path(for: root))' "o cwd do Codex deve ser o diretório remoto"
needF $C/CodexReadOnly.swift '"cwd": .string(RemoteExecution.path(for: root))' "o cwd do Codex (leitura) deve ser o diretório remoto"
needF $C/CodexReadTools.swift 'if let workspace = RemoteWorkspace.existing(at: root) { return try SSHReadTools.execute(workspace' "ferramentas de leitura devem ler o conteúdo do servidor"
run_tests remoteLaunchNeverUsesLocalBinaryAndBlocksPending remoteProjectsUseServerProviders
finish
