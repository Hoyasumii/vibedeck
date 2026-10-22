---
author: ai
---
# Contratos e compatibilidade

Estado: levantamento para revisão. Os contratos abaixo descrevem o atual ou metas já solicitadas; não impedem mudanças suas. Antes de remover um comportamento, registrar a decisão e os efeitos em dados, clientes e regras ativas.

## 1. Persistência do projeto — atual

vibedeck.json reúne metadados e coleções do projeto, como links, stack e padrões. .vibedeck/ reúne documentos, ideias, revisões, regras, agentes, comandos, skills, workflows, runs e checks. Docs são Markdown; registros são JSON com schema/identidade/autoria conforme o tipo.
ProjectStore fornece operações compartilhadas, com persistência por AtomicFile. O app observa arquivos e mantém estado de apresentação; isso não é armazenamento de domínio alternativo.
UUIDs, autoria, datas, relações e campos de compatibilidade precisam entrar na matriz de migração. Não basta comparar a formatação textual do JSON; round-trip deve demonstrar equivalência semântica e preservação dos campos necessários.

**Decidir:** continuar com os mesmos formatos, política de campos desconhecidos, concorrência entre processos e recuperação de arquivos inválidos. A ideia atual da reescrita exige compatibilidade; eventual mudança precisa atualizar essa decisão explicitamente.

## 2. Identidade e organização — atual

Referências aceitam caminhos/slugs e, conforme a operação, UUID, prefixo ou título. Referências ambíguas são recusadas. Docs/ideias/revisões/skills aceitam grupos aninhados. Movimentos preservam identidade e atualizam relações pertinentes; paths inseguros não devem escapar da raiz gerenciada.
Tags organizam e filtram; globs e referências explícitas determinam regras aplicáveis. Não usar uma tag como substituto de escopo.

## 3. CLI — atual e destino

O CLI atual é Swift e compartilha o Core. Famílias observadas incluem projeto/status, docs, review, rules, ideas, agents, commands, skills, workflows/runs, stack/patterns, groups, logs, cloud e mcp.
Saída humana e --json não são intercambiáveis; contratos precisam inventariar argumentos, defaults, erros e exit codes por comando. --ai identifica autoria onde existe.
A nova versão deve substituir o CLI conforme a ideia 04, mas a prova da etapa 02 não substitui o instalado.

**Decidir:** superfície mínima da prova, comandos removidos/renomeados e estratégia de compatibilidade. Inventário exaustivo das flags ainda deve ser gerado/revisado antes da migração.

## 4. MCP — atual

vibedeck mcp serve stdio. Ferramentas exemplares verificadas: read_doc/write_doc, list_ideas/get_idea/update_idea, item_groups, rules_for/submit_rule_check. O servidor também expõe outros recursos e ferramentas; essa lista não pretende esgotá-los.
A operação usa o projeto selecionado como raiz. stdout transporta mensagens MCP; intercalar logs ou partes de respostas corromperia a conexão. O transporte atual serializa envios.
O registro Codex documentado inclui adaptador de compatibilidade Python. O requisito futuro é eliminar esse preparo para operações básicas do binário Rust; não presumir que qualquer cliente remoto pode executar stdio.

**Meta confirmada:** artefatos pré-compilados por sistema/CPU, sem UI e sem toolchains no destino; leitura/escrita em projeto temporário em máquina limpa/local e ambiente SSH representativo.
**Decidir:** cliente, ambiente, instalação, atualização, argumentos e variáveis. MCP HTTP remoto não está aprovado. A distribuição mínima não dispensa autenticação do provider nem ferramentas exigidas por operações específicas.

## 5. Checks e scripts — atual

| Elemento | Comportamento atual |
| --- | --- |
| Escopo | Tópicos globais + por arquivos + explícitos/revisão |
| Resultado do script | 0=pass; 77=na; demais=fail |
| Ambiente | VIBEDECK_ROOT, VIBEDECK_FILES e VIBEDECK_RULE_ID |
| Limite | Timeout padrão de 120 s no runner de regras |
| Concorrência | Limitada; recursos da mesma ferramenta de build são serializados |
| Teste desatualizado | Hash deixa de corresponder; não vale como script atual |
| Manual automático | Fica pending |
| Manual explícito | Veredito/evidência para as manuais exigidas |
| must fail | Bloqueia aprovação |
| should fail | Produz aviso |
| Histórico | Novo check; não editar o anterior |

**Mudança confirmada:** piloto Rust com biblioteca/runner compartilhado. Compatibilidade de comandos antigos, agendamento, erro e cancelamento deve ser comprovada. Teste Swift ainda requer Swift, mesmo com runner Rust.

## 6. Ideias, planos e execuções — atual

Readiness corresponde ao conteúdo da ideia; dependências são UUIDs e precisam estar done antes de implementar. Proposta, aprovação, promoção e execução são eventos distintos.
Execução de workflow persiste provider, perguntas/respostas, histórico e checkpoints. Retomar preserva; reiniciar é explícito. A escolha de modelo/effort não pode ser trocada automaticamente se indisponível.
Manuais must necessárias ao fechamento de uma revisão continuam no gate dessa revisão.

**Decidir:** manter esses estados/gates e a diferença entre app e CLI/MCP. Transferência de sessão entre providers não foi definida.

## 7. Plataformas, SSH e recursos externos

Hoje o produto contém UI macOS e Swift Core/CLI; há adaptações Linux, mas isso não comprova uma versão distribuída/testada em todos os sistemas.
SSH executa ferramentas no servidor e sincroniza dados por cache. Nuvem inicia tarefas no serviço do provider. São contratos diferentes, não duas formas equivalentes de rodar tudo.
Credenciais e permissões são do ambiente/provider; não registrar segredos na especificação nem assumir que instalação local vale na nuvem.

## Matriz inicial de paridade a completar na etapa 01

| Contrato | Evidência | Comparação necessária |
| --- | --- | --- |
| Arquivos e IDs | ProjectStore, Models, schema/v1 | Leitura/escrita e relações sem perda |
| CLI/MCP | CLI.swift, MCPServer.swift | Comandos, ferramentas, schemas e erros |
| Regras/checks | RuleTests, RuleExecution, StopGate | Escopo, resultados, validade e bloqueios |
| Ideias/dependências | RulesTests e ProjectStore | Readiness, ciclos e bloqueio anterior à execução |
| Workflows | WorkflowRuns e respectivos testes | Transições, respostas e retomada |
| Providers | AIProvider e AIIntegration | Modelo, effort, permissões e erros sem fallback |
| SSH | RemoteWorkspace, RemoteExecution | Persistência de pendências e conflitos |
| UI | ProjectModel e ProjectWindow | Consulta/edição e efeitos ao trocar o Core |

Fontes: [guia atual](../../guide.md), [CLI](../../../Sources/vibedeck/CLI.swift), [MCP](../../../Sources/vibedeck/MCPServer.swift), [persistência](../../../Sources/VibeDeckCore/ProjectStore.swift), [runner](../../../Sources/VibeDeckCore/RuleTests.swift), [transport stdio](../../../Sources/vibedeck/SerializedStdioTransport.swift).

## Decisão do usuário — 22/10/2026

O produto passa a ter início guiado (stack, padrões e oferta de cadastro de skills/agentes/comandos existentes), Docs com Markdown da raiz espelhado por link simbólico e execução somente local ou SSH. Sessões de nuvem serão removidas. Ver [requisitos e pendências](07-mudancas-confirmadas.md). Estas são mudanças solicitadas, ainda não implementadas.

### Contratos afetados pelas novas decisões

Onboarding detecta recursos e pede consentimento para cadastro; detecção não equivale a importação. Preservar itens existentes e informar duplicatas.
Docs ganha vínculos por symlink para Markdown da raiz, como README.md; o destino é a fonte do conteúdo. Revisar validação de caminhos e escrita atômica para que leitura/edição suportada preserve o link e a origem. Definir suporte por plataforma e SSH.
A família cloud e as ferramentas de sessões de nuvem descritas como atuais serão retiradas: são exceções explícitas à paridade da migração. Definir transição para clientes/configurações antigos sem excluir dados silenciosamente.
