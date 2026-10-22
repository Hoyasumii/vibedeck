---
author: ai
---
# Decisões pendentes e migração

Estado: roteiro para revisão humana, atualizado em 22/10/2026. A direção geral está definida; detalhes em aberto não devem ser resolvidos como se você já tivesse aprovado.

## Decisões já expressas por você

- Facilitar desenvolvimento com IA para desenvolvedores/vibecoders e pessoas com pouco conhecimento de programação.
- Ideias refinadas com limites, documentação, stack/padrões, cliente de IA, recursos reutilizáveis, workflows e revisões.
- Produto multiplataforma, com Core, CLI e MCP em Rust.
- MCP por stdio utilizável por outras ferramentas/máquinas em execução local ou por SSH com pouco preparo.
- App macOS e CLI urgentes; Windows/Linux na próxima atualização, conforme a tabela humana.
- Referência visual fornecida no documento 01.
- Você vai revisar o inventário e retirar/mudar recursos; o comportamento atual não está automaticamente aprovado como destino.

## Perguntas para sua revisão

| ID | Decisão pendente | Contexto atual / opções a avaliar |
| --- | --- | --- |
| DEC-001 | Cliente e ambiente SSH prioritários | Nuvem removida do escopo; escolher máquina local limpa e servidor SSH para a prova |
| DEC-002 | Sistemas e CPUs da primeira entrega | macOS/CLI urgentes; definir Linux da prova, Windows e arquiteturas |
| DEC-003 | Distribuição e atualização | Artefatos pré-compilados são a direção; atualização automática confirmada (MUD-004), mas fora da primeira versão; UPD-001…008 do [doc 10](10-atualizacao-automatica.md) ficam para depois |
| DEC-004 | Operações mínimas MCP | Selecionar leitura e escrita representativas, com contratos atuais |
| DEC-005 | Regras do piloto | Selecionar 3 a 5, incluindo resultado válido, erro e não aplicabilidade |
| DEC-006 | Fronteira SwiftUI/Rust | Processo/JSON versus biblioteca/FFI; escolher após avaliação pequena |
| DEC-007 | Destino dos recursos existentes | Marcar manter/mudar/retirar nos 12 documentos de funcionalidades |
| DEC-008 | Troca de provider | Hoje inicia conversa nova; decidir transferência de contexto e continuidade |
| DEC-009 | Providers adicionais | OpenCode foi citado; escolher se/quando entra e quais capacidades |
| DEC-010 | Regras e gates de ideias | Revisar readiness, promoção, manuais e o momento de concluir automaticamente |
| DEC-011 | Workflows versus nextSteps | Definir se ambos ficam e como simplificar a experiência |
| DEC-012 | Coleção Claude, grafo e terminal | Revisar prioridade; execução local e SSH foram confirmadas, sessões de nuvem serão removidas |
| DEC-013 | Significado de aprovação e economia | Definir amostras, critérios de primeira aprovação e métricas |
| DEC-014 | Dados e compatibilidade | Ideia atual exige paridade; registrar exceções desejadas e eventual migração |
| DEC-015 | UI Windows/Linux | Esclarecer se próxima atualização significa interface gráfica ou primeiro CLI/MCP |
| DEC-016 | MCP quando stdio não for possível | Transporte remoto por rede não decidido; pode exigir ampliar escopo |
| DEC-017 | Referência visual | Confirmar telas/fluxos prioritários; conteúdo externo não foi inspecionado nesta coleta |

## Ordem registrada nas ideias

1. **Arquitetura/padrões** — UUID 32390FB1-061D-45DE-ACC8-24D717FF880A.
2. **Core mínimo + MCP stdio local/em ambiente limpo e por SSH** — 6AC91755-1DDC-487F-9554-344E0E95C258.
3. **Piloto de regras Rust** — 5FE68368-901F-4643-8A35-427C7EBEE15B.
4. **Concluir Core/CLI/MCP e integrar app** — 35806341-8605-43B0-A13A-456DB1369B35.
5. **Medições e melhorias posteriores** — C17132D2-9CAA-4981-A4B5-81CBE4550AA8.

As dependências estão gravadas nessas ideias; ler o estado atual antes de executar. Esta documentação não as marca como prontas nem concluídas.

## Fatias de migração — proposta, ainda não cronograma fechado

| Momento | O que entregar | O que continua existente |
| --- | --- | --- |
| Arquitetura | Contratos, fronteiras, distribuição e amostra | Toda a aplicação Swift atual |
| Prova MCP | Biblioteca mínima, operações reais e binário distribuível | CLI instalado/app/MCP completo não são substituídos |
| Piloto regras | Runner/biblioteca e regras selecionadas com paridade | Demais scripts e ferramentas de projeto |
| Domínio | Persistência e operações selecionadas em Rust | Módulos ainda não migrados com fronteira explícita |
| Integração | CLI/MCP completos, ponte do app e instalação | Apenas UI/adaptadores necessários em Swift |
| Consolidação | Remover duplicação após evidências | Formatos/contratos aprovados preservados |

A ordem interna dos módulos depende de DEC-007/014. Não desenhar crates por hábito ou converter linhas de código sem validar comportamento.

## Como transformar sua leitura em decisões

Em cada documento, escreva o resultado desejado junto da descrição atual. Preservar evidências históricas pode ajudar, mas a decisão de destino deve ficar clara.
Quando houver conflito com regra ativa ou com as regras rascunho de uma ideia, registrar a alteração necessária e atualizar o item apropriado antes de implementar. Não promover regras por esta revisão.
Se você remover um recurso, definir o destino dos dados existentes e o comportamento de clientes/comandos que o utilizam.

## Primeira sessão de implementação

Ler índice, ideia e áreas afetadas; resolver bloqueios; consultar stack/padrões/revisões; obter avaliação e escolher forma de execução conforme o fluxo do VibeDeck. Usar provider codex nas operações que aceitam provider e preservar modelo/permissões escolhidos.
O preenchimento atual é preparação documental. Não iniciou a reescrita nem modificou código ou regras ativas.

## Decisão do usuário — 22/10/2026

O produto passa a ter início guiado (stack, padrões e oferta de cadastro de skills/agentes/comandos existentes), Docs com Markdown da raiz espelhado por link simbólico e execução somente local ou SSH. Sessões de nuvem serão removidas. Ver [requisitos e pendências](07-mudancas-confirmadas.md). Estas são mudanças solicitadas, ainda não implementadas.

### Novas decisões confirmadas e detalhes pendentes

MUD-001 confirmado: início guiado com stack, padrões e oferta de cadastro dos recursos existentes. Decidir gatilho, pular/retomar e tratamento de duplicatas.
MUD-002 confirmado: Docs espelha Markdown da raiz por link simbólico. Decidir seleção automática/manual, edição, links quebrados e comportamento por plataforma.
MUD-003 confirmado: remover sessões de nuvem e manter local/SSH. Decidir migração de configurações, comandos e históricos. Não é mais pendente decidir se manter SSH ou sessões de nuvem.
O rascunho de regra 13D1425F-0210-42DD-B667-A24FFDA86743 ainda menciona nuvem: está revogado pela decisão, com revisão estruturada pendente antes de promover a ideia 04.

## Stack e padrões já cadastrados

A consulta em 22/10/2026 encontrou 7 tecnologias e 21 padrões, com 57 regras (48 must e 9 should), todos com escopo global. A lista, notas, tópicos e regras estão em [08 — Stack e padrões](08-stack-e-padroes-do-projeto.md).
A etapa 01 deve partir desse cadastro: definir uso concreto por módulo sem cadastrar uma arquitetura paralela só nos documentos. Pendências: finalidade do Zod, versões/notas do Rust e MCP, atualização das notas históricas de Swift e eventual delimitação de globs dos padrões. As regras atuais continuam vigentes até alteração explícita.
Cloudflare Workers/TypeScript estão associados aos schemas; não confundir essa infraestrutura com a feature de sessões de nuvem que será removida.
