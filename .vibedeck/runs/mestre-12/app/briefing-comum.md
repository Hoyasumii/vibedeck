# Briefing comum — migração do app macOS para o Core Rust (APP-2b)

Leia inteiro antes de editar. Sem Git. NÃO há Swift nem CI agora: nada será compilado até a CI voltar. Escreva Swift CONSERVADOR,
confira TODA assinatura por grep antes de usar, evite cadeias longas de modificadores e expressões complexas (o type-checker do Swift é lento),
app em Swift 5 language mode (`swiftLanguageMode(.v5)`), macOS 26. Português nas mensagens ao usuário, como já é.

## Objetivo
O target `VibeDeckApp` NÃO pode importar `VibeDeckCore` (decisão D12). O Core Swift (`Sources/VibeDeckCore`), a CLI Swift (`Sources/vibedeck`) e
`Tests/VibeDeckCoreTests` serão apagados pelo líder no fim. O app passa a ser CLIENTE MCP do binário Rust `vibedeck mcp -C <raiz>`
(local) ou `ssh host vibedeck mcp -C <raiz>` (SSH): `Sources/VibeDeckApp/Core/CoreClient.swift` (já escrito) + `CoreStore.swift` (já escrito).
Nuvem (D5) sai da UI: nada de `CloudSession`, `CloudLaunchSheet`, `codexCloudEnvironment`, botões de sessão na nuvem.

## Arquitetura (já decidida — não reabra)
- `CoreClient` (Core/CoreClient.swift): `callTool(name, arguments:)`, `readResource(uri)`, `listResources()`. LEIA o arquivo.
- `CoreStore` (Core/CoreStore.swift) substitui `ProjectStore`: mesmas URLs puras (`docURL`, `topicURL`, `docsDir`...), `root`, e métodos
  ASSÍNCRONOS (`loadProject`, `listDocs`, `readDoc`, `listTopics`..., `saveRecord`, `deleteRecord`, `saveProject`, `writeDoc`, `createDoc`,
  `callJSON(tool, args)`, `call(tool, args)`, `itemGroups`...). `CoreStore` NUNCA lê/escreve `.vibedeck/` diretamente: tudo via MCP.
- Catálogo REAL das tools: `.vibedeck/runs/mestre-12/app/tools.md` (gerado do binário). Contratos de saída: `crates/vibedeck/src/mcp/tools/*.rs`.
  Você pode rodar o binário real para ver saídas: `/home/user/vibedeck/target/release/vibedeck mcp -C <pasta>` (use CÓPIA do projeto; ex.:
  `/tmp/claude-0/-home-user-vibedeck/94651eed-02f2-5d06-a595-e639a14737e5/scratchpad/proj` e o cliente `.../scratchpad/mcp.py`
  — função `session(root, [(método, params)])`). NUNCA rode contra /home/user/vibedeck (o servidor reescreve .vibedeck/AGENTS.md).
- Leitura de registros: `resources/read vibedeck://{reviews,rules,ideas,agents,commands,skills,workflows}/<slug>` devolve o JSON CRU do arquivo
  = mesmo formato que os tipos Codable Swift (`ReviewGroup`, `RuleTopic`, `Idea`, `Agent`, `Command`, `Skill`, `Workflow`) já decodificam.
  Por isso os TIPOS DE DADOS do Core Swift são MOVIDOS para o app (abaixo) e continuam sendo o modelo da UI.
- Escrita: tools existentes quando houver (veja tools.md); senão as tools PEDIDAS ao Core (put_record, delete_record, put_project, list_checks...,
  ver `.vibedeck/runs/mestre-12/app/pedidos-core.md`). Já estão encapsuladas em `CoreStore` (chamam a tool; se ela não existir lança
  `CoreError.unsupported`). Operação que o Core não oferece: lance `CoreError.unsupported("nome")`, mostre `errorMessage`, e registre um PEDIDO-CORE
  no SEU arquivo de notas (formato: tool, argumentos, retorno, quem chama).
- Raiz do projeto: pasta local OU URL `ssh://[user@]host[:porta]/dir[?alias=x]` (projeto SSH; ver `Core/RemoteWorkspace.swift`, já escrito:
  `RemoteWorkspace.existing(at:)` devolve o destino SSH; NÃO existe mais espelho local nem sincronização — apague tudo que sincroniza/resolve conflitos).
  Coisas locais (Finder, Terminal local, cwd de processos, arquivos de anexo) só fazem sentido quando `store.isRemote == false`.
- `ProjectModel` (Sources/VibeDeckApp/ProjectModel.swift) é do LÍDER e está sendo reescrito. API pública que as views usam PERMANECE
  (`model.docs/groups/topics/ideas/...`, `model.mutateIdea(...)`, `model.createDoc(title:)`, `model.reloadTopics()`, `model.errorMessage`, `model.store.root`, ...).
  Mudanças conhecidas: `ProjectModel(store:)` some; vira `static func open(root: URL) async throws -> ProjectModel` (a janela mostra "Carregando…"
  e erro com "Tentar de novo"); `model.store` é `CoreStore`; `model.store.<IO síncrono>` (loadIdea, loadTopic, listX, readDoc, startRun...) NÃO existe mais:
  use o estado em memória do model (`model.idea(slug)`, `model.topic(slug)`, ...) ou chame o método async do CoreStore dentro de `Task { }`.
  Se precisar de método novo no model, anote "PEDIDO-MODEL: assinatura exata + semântica" no seu arquivo de notas (o líder implementa).
  NÃO edite ProjectModel.swift.
- Operações que antes eram síncronas e agora são assíncronas: envolva em `Task { @MainActor in ... }` / `await`, atualize estado com `defer`/flags.
  Preferir `do { try await ... } catch { model.errorMessage = error.localizedDescription }`.

## O que foi MOVIDO do VibeDeckCore para o app (executores P*)
Tipos de dados e lógica PURA/App-only do Core Swift passam para `Sources/VibeDeckApp/Core/` com os MESMOS nomes e membros (copiar, não renomear;
remover só o que depende de `ProjectStore`/disco do projeto/nuvem). Subpastas: `Core/Model` (dados do projeto), `Core/AI` (provedores, chat,
streaming, codex, uso), `Core/Discover` (prompts/schemas/parse das descobertas com IA), `Core/Support` (Logging, FileWatcher, SSH, AtomicFile...).
Nomes de ARQUIVO precisam ser únicos no target (SwiftPM/swiftc recusa dois `Foo.swift`): os arquivos movidos que colidem com arquivos do app
(`ReviewDiscover.swift`, `RuleDiscover.swift`, `DocGenerate.swift`) recebem sufixo `Logic` (ex.: `ReviewDiscoverLogic.swift`). Confira com
`find Sources/VibeDeckApp -name '*.swift' | sed 's#.*/##' | sort | uniq -d` (deve ficar vazio).
Tipos duplicados: confira por grep que nenhum `struct/enum/class Foo` fica declarado duas vezes.
`public` pode ficar (inofensivo em target executável) mas NÃO é necessário em código novo.

## Regras ao mover/portar código
1. Remova `extension ProjectStore {...}` e tudo que lê/grava o projeto em disco. Para cada função removida que o app USA (grep em `Sources/VibeDeckApp` e `Tests/VibeDeckAppTests`):
   (a) pura e pequena (validação, formatação, cálculo sobre valores) -> porte como função pura (estática no tipo ou função livre) recebendo os dados por parâmetro;
   (b) existe tool no Core -> método async em `extension CoreStore` no seu próprio arquivo `Core/CoreStore+<Area>.swift`;
   (c) senão -> `CoreError.unsupported` + PEDIDO-CORE.
2. `VibeDeckError` (de ProjectStore.swift) vai para `Core/Model/VibeDeckError.swift` SEM os casos de nuvem (`cloud*`, `claudeNotInstalled` se só nuvem usava),
   mantendo `errorDescription` literal dos demais. Adicione casos novos só se precisar.
3. `VDLog`/`LogStore`/`LogEntry`/`CrashSentinel` (Logging.swift) ficam no app tal como estão (log do próprio app; o Core Rust tem o dele).
4. Nada de `import VibeDeckCore`. Nada de `ProjectStore` (use `CoreStore`). Nada de `AtomicFile.write` sobre `.vibedeck/` (AtomicFile pode ficar só para arquivos do próprio app: chats, cache).
5. Mantenha comentários úteis; corrija os que citarem o que não existe mais.
6. Cada executor escreve notas em `.vibedeck/runs/mestre-12/app/notas-<fatia>.md`: arquivos criados/alterados/apagados, o que foi DESCARTADO de cada arquivo do Core
   (função -> destino a/b/c), PEDIDO-CORE, PEDIDO-MODEL, APIs Swift de risco, dúvidas. Curto e objetivo.
7. Só edite os arquivos da SUA fatia. Se a mudança precisa tocar arquivo de outra fatia, anote em PEDIDO-FATIA no seu notas.

## Verificação que VOCÊ deve fazer antes de terminar (não há compilador)
- `grep -n "VibeDeckCore\|ProjectStore\|CloudSession\|CloudLaunch\|codexCloud" <seus arquivos>` -> vazio.
- Para cada símbolo que você usa e não declarou: `grep -rn "func nome\|struct Nome\|enum Nome\|class Nome\|var nome\|case nome" Sources/VibeDeckApp` para confirmar que existe
  (com a assinatura/labels exatos). O que for declarado em arquivos de OUTRAS fatias (em andamento) confira no código ORIGINAL em `Sources/VibeDeckCore` — ele será movido sem mudar assinatura.
- Releia seu diff linha a linha procurando: `try` faltando, `await` faltando, closure `@MainActor` chamando async sem Task, variável não usada, retorno faltando, `switch` não exaustivo,
  labels de argumento trocados, uso de membro `private` de outro arquivo, tipos Optional.
- Final: lista curta com as APIs Swift de maior risco que você usou.

## Dicas Swift específicas
- `Process`/`Pipe`: `readabilityHandler` roda em fila de fundo; não toque UI ali. `FileHandle.write(contentsOf:)` lança.
- Em Swift 5 mode, Sendable é só aviso; mesmo assim marque closures `@Sendable` quando já estavam.
- `Observation`: `@Observable` classes com `@MainActor`; propriedades mutáveis lidas por views precisam ser armazenadas (não computadas) para observar.
- Não use APIs novas que você não conhece com certeza (macOS 26 SDK). Prefira as que o código existente já usa.
