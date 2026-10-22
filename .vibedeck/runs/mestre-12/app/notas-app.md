# APP-2b — notas do líder (não compilado: sem Swift)

Arquitetura: `CoreClient` (MCP stdio, ids, timeout, reconexão, local/SSH) + `CoreStore` (fachada async; leitura por `vibedeck://` e tools; escrita por tools + PEDIDOS) + `ProjectModel` (espelho em memória, otimista, fila serial de gravação, releitura adiada enquanto há gravação, FSEvents local / polling 6 s em SSH).
Projeto remoto = URL `ssh://user@host[:porta]/dir[?alias=x]` (Core/RemoteWorkspace.swift); sem espelho/sincronização.
Janela: `ProjectWindowV2` abre o modelo (async) e mostra Carregando/erro; `ProjectWindowV2Content` é a casca V2.
Removido: CloudLaunchSheet e botão "Sessão na nuvem", ProjectWindow (V1; só restou NewNamePrompt/NamePromptSheet em V2/V2NamePrompt.swift), Aliases.swift (Link -> ProjectLink), RemoteProjectBar/conflitos.
Package.swift: só VibeDeckApp (+ GraphResources) e VibeDeckAppTests; sem ArgumentParser/swift-sdk. Package.resolved sem eventsource/swift-sdk.
scripts/build-app.sh: cargo build --release -p vibedeck (ou VIBEDECK_BIN) -> Contents/MacOS/vibedeck. scripts/test.sh: cargo test + swift test.
Testes: removidos os que dependiam do ProjectStore Swift (cobertura vai para o Rust); novos CoreClientTests (servidor MCP falso em sh) e CoreModelsTests; CommitTextField/GraphRunner/AIRecovery adaptados; `ProjectModel.forTesting`.
Fora do escopo/pendente fora de Sources/VibeDeckApp: scripts/test-rule-helpers.py, audit-rule-scripts.sh, mcp-contract.py ainda citam Tests/VibeDeckCoreTests e Sources/VibeDeckCore (donos: CORE/regras).
