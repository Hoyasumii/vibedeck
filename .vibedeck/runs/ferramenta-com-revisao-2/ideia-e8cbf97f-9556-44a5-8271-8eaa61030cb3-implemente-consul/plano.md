# Plano — Visualização de Execução de Workflow (ideia E8CBF97F, tópico `visualizacao-de-execucao-de-workflow`)

## Contexto verificado
- Stack: Swift 6.2/SwiftUI macOS 26; Core compila também em Linux (sem SwiftUI no Core). Sem padrões de projeto cadastrados. Revisões abertas não tocam esta área.
- `WorkflowDiagram` (App) recebe só `steps/title/open`; `focus`/`isOn` é interno (hover). Não conhece `current` nem histórico.
- `ClaudeChat` (Core/ClaudeChats.swift) não tem referência à execução; `ClaudeSession.resumeWorkflow` usa `workflowRef` só em memória.
- `ClaudeStream.parse` descarta eventos com `parent_tool_use_id` (`.ignored`); `ClaudeEvent` não tem eventos de agente.
- `WorkflowRun` já tem `status`, `current`, `history` (`WorkflowRunEntry.step/next/cycle`).

## Módulos (responsabilidade única)
1. **Core `WorkflowRunPath`** (novo, `VibeDeckCore/WorkflowRunPath.swift`): função pura `traversed(run, workflow) -> Set<EdgeKey>` a partir de `history` (`step → next`, incluindo loops) + `currentStep`. Testável no Linux.
2. **Core `AgentProcess`/`AgentProcessTracker`** (novo, `VibeDeckCore/AgentProcesses.swift`): `struct AgentProcess {id, name, parentID?, state: running|succeeded|failed|interrupted, startedAt, endedAt?}` e `AgentProcessTracker` (reducer sobre `AgentLifecycleEvent.started/finished(id,parent,outcome)`). Só eventos reais criam/atualizam; término mexe apenas no id correspondente.
3. **Core `ClaudeStream`**: novo `ClaudeEvent.agent(AgentLifecycleEvent)`: início = `tool_use` de `Task`/`Agent` (id = tool_use id), término = `tool_result` com esse `tool_use_id` (is_error → failed); eventos com `parent_tool_use_id` deixam de ser descartados cegamente: ainda não geram texto/tool no chat, mas fornecem `parentID` aos agentes filhos. Interrupção: `result.isInterrupted` marca abertos como interrupted.
4. **Core Codex** (`AIConversationTransport`/`CodexEventStream`): mapear itens de colaboração/subagente do app-server (início/fim com thread id e id do pai) para o mesmo `AgentLifecycleEvent`. **Risco:** formato exato dos eventos Codex precisa ser confirmado lendo o protocolo/gerando fixture real na implementação; sem inventar.
5. **Core `ClaudeChat`**: novo campo opcional `workflowRun: String?` (ref `<workflow>/<run>`), decode `decodeIfPresent` (compatível), + `agentProcesses` persistido com `savedAt`. Atualizar schema/doc se o formato for exposto.
6. **Reabertura**: ao carregar chat, processos salvos como `running` viram `unconfirmed`/`interrupted` salvo confirmação de atividade (sessão do provedor viva nesta execução do app). Regra pura no tracker (`reconcile(alive:)`), testada.
7. **App `WorkflowDiagram`**: parâmetros opcionais `current: String?`, `traversed: Set<EdgeKey>` (padrão vazio → sem mudança nas telas atuais); destaque da etapa atual e das arestas percorridas.
8. **App `WorkflowRunPanel`** (novo): cabeçalho com estado (4 `WorkflowRunStatus` com cor/ícone/texto pt-BR distintos; `waiting` sem indicador de atividade), `WorkflowDiagram` e lista de processos (pai/filho, estado). Botões ocultar e expandir/restaurar.
9. **App `ClaudeChatPage`**: composição chat + painel com `HSplitView`/divisor arrastável; abre automaticamente em `executeWorkflow`/`resumeWorkflow`; estado de visibilidade/expansão por chat (ocultar não cancela `workflowTask`); exibe só o run do chat selecionado (lido via `ProjectModel.runs` pela ref persistida).
10. **App `ClaudeSession`**: grava `workflowRun` no chat ao iniciar/retomar; alimenta o tracker com eventos; limpa/rehidrata ao trocar de chat.

## Critérios de aceite → verificação
- Core (`swift test`): traversed com ramificação+loop; tracker com 2 subagentes sobrepostos, pai correto, falha/cancelamento isolados, texto que menciona agentes não cria processo; fixtures de stream Claude (com `parent_tool_use_id`) e Codex; round-trip/compat de `ClaudeChat` (renomear/recarregar mantém ref; JSON antigo decodifica); reconcile ao reabrir.
- App (manual, regras manuais da ideia): auto-abrir, arrastar, expandir/restaurar, ocultar/reabrir, destaque, estados, isolamento entre conversas.
- Ao fim: `rules_for` nos arquivos alterados + `submit_rule_check` até passed=true; `graphify update .`.

## Ordem de implementação
Core (1,2,5,3,4,6) com testes → App (7,8,9,10). Cada passo pequeno e commitável.

## Decisões assumidas (sem bloquear)
- Painel à direita do chat, largura padrão ~40%, mínimo 280pt.
- Ref persistida como string `<workflow>/<run>` (mesmo `slug` de `runs`).
- Processos órfãos ao reabrir aparecem como "interrompido (não confirmado)", nunca "em andamento".

PLANEJADO
