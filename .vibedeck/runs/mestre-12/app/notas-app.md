# APP-2b — notas do líder (não compilado: sem Swift)

Arquitetura: `CoreClient` (MCP stdio, ids, timeout, reconexão, local/SSH) + `CoreStore` (fachada async; leitura por `vibedeck://` e tools; escrita por tools + PEDIDOS) + `ProjectModel` (espelho em memória, otimista, fila serial de gravação, releitura adiada enquanto há gravação, FSEvents local / polling 6 s em SSH).
Projeto remoto = URL `ssh://user@host[:porta]/dir[?alias=x]` (Core/RemoteWorkspace.swift); sem espelho/sincronização.
Janela: `ProjectWindowV2` abre o modelo (async) e mostra Carregando/erro; `ProjectWindowV2Content` é a casca V2.
Removido: CloudLaunchSheet e botão "Sessão na nuvem", ProjectWindow (V1; só restou NewNamePrompt/NamePromptSheet em V2/V2NamePrompt.swift), Aliases.swift (Link -> ProjectLink), RemoteProjectBar/conflitos.
Package.swift: só VibeDeckApp (+ GraphResources) e VibeDeckAppTests; sem ArgumentParser/swift-sdk. Package.resolved sem eventsource/swift-sdk.
scripts/build-app.sh: cargo build --release -p vibedeck (ou VIBEDECK_BIN) -> Contents/MacOS/vibedeck. scripts/test.sh: cargo test + swift test.
Testes: removidos os que dependiam do ProjectStore Swift (cobertura vai para o Rust); novos CoreClientTests (servidor MCP falso em sh) e CoreModelsTests; CommitTextField/GraphRunner/AIRecovery adaptados; `ProjectModel.forTesting`.
Fora do escopo/pendente fora de Sources/VibeDeckApp: scripts/test-rule-helpers.py, audit-rule-scripts.sh, mcp-contract.py ainda citam Tests/VibeDeckCoreTests e Sources/VibeDeckCore (donos: CORE/regras).

## APP-3 (executor Sonnet) — SSH offline, bugs, duplicatas (não compilado)
- D16: `Core/RemoteLink.swift` (novo): `RemoteLink` (estados connected/connecting/waiting(until)/offline, laço 0,5 s, sonda `project_revision` a cada 6 s -> relê tudo se mudou, reconexão 1,2,4…60 s, `reconnectNow`), `RemoteBackoff`, `RemoteCache` (última leitura em Application Support/VibeDeck/RemoteCache/<id>.json, inclui textos de docs, runs, checks). `CoreClient.reset()` derruba sessão pendurada. `ProjectModel.link/isReadOnly`: `persist` recusa edição offline (erro + volta à última leitura), `refresh` não lê offline, `open` abre do cache se o servidor estiver inalcançável. UI: `V2OfflineBanner`, `V2RemoteEnvironmentSegment(link:)` (conectado / reconectando · próxima tentativa em Ns / offline somente leitura), detalhe e ações de criar/apagar/tags da coluna desabilitados offline. Removidos `RemoteProjectStatus`, polling de 6 s e texto de conflito/pendências (AgentsGuide).
- Bug 48989eac: `ReviewDiscoverRunner.run` (morto, sem configure) removido; `AIReadOnlyOperation` usa `AIReadOnlyProcess.run`.
- Bug 8a34ae9e: `addKitItems` registra 1 passo de undo/redo (cria/remove os itens novos via put_record/delete_record), `author: human`.
- 7d9e4052: reinício usa `workflow_run_restart(run)` (`CoreStore.restartRun`) em `prepareIdeaImplementation`; sem `restart:true`.
- Duplicatas: catálogo de padrões Swift removido (Patterns.swift só ProjectPattern/PatternCategory; `VibeDeckError.unknownPatterns` removido); `PatternsView` usa `pattern_catalog` (`CoreStore.patternCatalog`). DocGenerate (prompt/schema/parse) PERMANECE: o Core só tem a parte pura em Rust (docs/generate.rs), sem tool MCP; pedir `doc_generate_*` ou manter.
- Órfãs: `release_orphaned` chamado ao abrir, após mudança externa (tópicos/ideias/projeto) e ao reconectar; relê se algo foi solto. `add_pattern`/`add_kit` enviam `author: human`.
- Riscos de compilação: `RemoteCache.Record<Value>` genérico aninhado; `@Observable` + closures em `init` de ProjectModel; `TimelineView` em V2RemoteEnvironment; `.disabled` no detalhe pode bloquear navegação interna offline; directoryGroups não vão ao cache; notificações resources/list_changed ainda não usadas (sonda por revision).
