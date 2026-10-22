---
author: ai, human
---
# 01 — Visão do produto

# Visão do produto

Estado: rascunho preenchido para revisão. Respostas humanas abaixo preservadas; complementos da IA identificados como propostas.

## Problema e objetivo

1. Que problema o VibeDeck resolve?
> A ideia do VibeDeck é poder facilitar o desenvolvimento de sistemas que usam Inteligência Artificial para criação, entregando um espaço onde o desenvolvedor consegue:
> - Anotar suas ideias para serem refinadas e aprimoradas de modo que na implementação, ela se integre com o sistema e declare limites em suas funcionalidades, para que no futuro, futuras modificações não quebrem as funcionalidades já existentes. A meta é que essas ideias quando implementadas criem regras no próprio sistema e sirvam como conceitos do próprio projeto;
> - Documentar links, e arquivos em Markdown, para que possa ser acessado tanto por quem desenvolve, como também pela própria IA;
> - Entrega uma coleção de possíveis Stacks e Padrões de Projeto, que vai permitir tanto que a IA, quanto quem estiver desenvolvendo, de desenvolver a risca desses conceitos. A meta é que quando houver um PR, o usuário revisar e ver se os padrões do projeto foram usados para resolver o problema. No caso da IA, ela sempre vai seguir com base nas Stacks do Projeto e nos Padrões;
> - Entregar um Cliente de IA dentro do próprio Projeto, que consegue interagir com todas as informações do VibeDeck (via MCP). A ideia é que o usuário possa trocar os provedores (Claude -> Codex; ou vice-versa; OpenCode -> Claude, por aí vai), e o provedor fazer perguntas e executando planos; 
> - Criar uma funcionalidade que espelha os Agenstes/Skills/Comandos do Claude Code. De modo a possibilitar que isso possa ser usado dentro do próprio VibeDeck. A cartada final é a feature de Workflow, que serve para orquestrar um fluxo inteiro de comandos(que podem receber prompts extras e criar vínculos entre os comandos e os agentes);
> - Criar pontos de revisões para sempre que for necessário, o desenvolvedor ir até esses pontos para resolver essas falhas.
2. Quem usa e em quais situações?
> 1. Vibecoders e Desenvolvedores que mantém projetos e precisam de um controle sobre o código a ser gerado. As regras informam à Inteligência Artificial os limites sobre as novas features e sobre as features já existentes;
> 2. Pessoas com pouco conhecimento em programação, ou até possuem, e reconhecem que a inteligência artificial consegue fazer o trabalho sujo(programação) para criar um produto. Restanto apenas a parte de negócios para o usuário;
3. Como saber que o produto cumpriu seu objetivo?
> 1. Quando se é possível implementar uma Task inteira de trabalho gastando poucos tokens e fazendo com que ela seja aprovada de primeira;
> 2. Quando o usuário com pouco conhecimento conseguiu desenvolver um projeto inteiro;
> 3. Quando todas as funcionalidades funcionam como deveriam funcionar;

## Direção confirmada

Produto multiplataforma:
- Core, CLI e MCP em Rust;
- Interface deriva desse [link](https://claude.ai/artifact/M9YGSGjtpf3mkMVd4TP1hr#artboard-e259634e05c3);
- MCP por stdio para outras máquinas, com execução local ou por SSH. Atualização explícita do usuário em 22/10/2026: remover sessões de nuvem do VibeDeck;

## Interfaces e plataformas

| Interface/ambiente | Público e uso | Prioridade | Limites e pré-requisitos |
| --- | --- | --- | --- |
| App macOS | O App deverá entregar um caminho fácil e visualizável de como o aplicativo funciona por baixo dos panos | Urgente | [PREENCHER] |
| CLI | Deverá | Urgente | [PREENCHER] |
| MCP por stdio | A ideia é que todos que usem Claude/Codex e outras ferramentas tenham acesso ao MCP para que a IA interaja com o próprio conteúdo do VibeDeck | Confirmado como meta | [PREENCHER] |
| Windows/Linux | [PREENCHER interfaces previstas] | Próxima Atualização| [PREENCHER] |

## Complementos de contexto — proposta da IA para revisão

O produto atual combina app macOS, CLI e MCP Swift com dados dentro do repositório. Os providers implementados são Claude e Codex; OpenCode foi mencionado por você como direção, não como recurso atual.
A linha CLI ficou iniciada como “Deverá”. Sugestão de complemento: permitir operar e automatizar o projeto pelo terminal, com saídas estruturadas para IA, independentemente da interface gráfica.
A tabela humana prioriza macOS e CLI como urgentes e Windows/Linux para a próxima atualização. Ainda falta decidir se isso inclui UI nessas plataformas ou primeiro Core/CLI/MCP.
A referência de interface fornecida por você foi mantida. Seu conteúdo visual não pôde ser acessado pela ferramenta de consulta; não inferi telas ou requisitos a partir dela.

## Jornada principal — síntese proposta

1. Abrir/criar projeto com guia que pergunta stack e padrões e oferece cadastrar skills, agentes e comandos já presentes, mediante escolha do usuário.
2. Documentar contexto, links e ideias; refinar escopo, limites e critérios.
3. Escolher provider e preparar uma tarefa ou fluxo reutilizável.
4. A IA consulta o contexto necessário, resolve dúvidas e apresenta plano quando exigido.
5. Usuário escolhe/autoriza o caminho de implementação.
6. Executar, acompanhar perguntas/progresso e interromper se necessário.
7. Verificar regras e critérios; corrigir falhas e registrar evidências.
8. Revisar resultado, registrar pendências e consolidar regras quando solicitado.
9. Retomar em outra sessão/máquina com os registros do projeto como contexto compartilhado.

Esse fluxo sintetiza recursos existentes e objetivos humanos; detalhes de aprovação e promoção ainda podem mudar na sua revisão.

## Escopo por entrega — proposta baseada nas ideias organizadas

- Primeira decisão: arquitetura, contratos e destino dos recursos atuais.
- Primeira entrega executável: Core mínimo e MCP Rust por stdio em máquina limpa/local e por SSH, com leitura/escrita e instalação documentadas.
- Em seguida: piloto de 3 a 5 verificações Rust.
- Depois: restante do Core, CLI/MCP e integração com o app, preservando ou alterando comportamentos conforme suas decisões.
- Depois da migração: otimização orientada por medições. Regressões precisam ser tratadas em qualquer etapa.

Não há decisão de converter todos os scripts, suportar todo provider, entregar UI Windows/Linux ou adicionar MCP HTTP na primeira entrega.

## Qualidades esperadas — proposta para revisão

**Instalação e atualização:** binários pré-compilados por destino, configuração pequena e documentação de pré-requisitos. Rust/Swift/Python/Node não devem ser necessários para iniciar o MCP Rust e operar funções básicas. Ferramentas do projeto continuam necessárias apenas para as operações que as usam.
**Manutenibilidade:** uma fonte de lógica de domínio, módulos com responsabilidades claras, contratos e testes de comportamento; app/CLI/MCP usam o mesmo Core.
**Compatibilidade:** inventariar arquivos, comandos e ferramentas antes de substituir a implementação. Mudanças desejadas por você devem ser explícitas, com estratégia de transição.
**Desempenho e consumo:** medir tempo até conclusão, retrabalho, tokens informados e tarefas concluídas. Os objetivos humanos de “poucos tokens” e “aprovada de primeira” são metas a operacionalizar, não garantias atuais.

## Perguntas que continuam com você

- O que significa “aprovada de primeira”: passar scripts, revisão humana, CI/PR ou todos?
- Qual ambiente SSH e cliente MCP devem funcionar na primeira prova?
- Como deve ocorrer a troca de provider: nova conversa, contexto transferido ou continuidade da mesma tarefa?
- Quais recursos atuais devem sair ou mudar?
- Qual papel o produto assume para quem sabe pouco programar: orientar, executar com aprovação ou automatizar etapas inteiras?
- Quais métricas e amostras demonstram economia e sucesso sem sacrificar correção?

## Evidências do complemento

[Manifesto de build atual](../../../Package.swift), [providers implementados](../../../Sources/VibeDeckCore/AIProvider.swift), [guia operacional](../../guide.md), [inventário](02-inventario-de-funcionalidades.md) e ideias do grupo criacao-do-core.

## Decisão do usuário — 22/10/2026

O produto passa a ter início guiado (stack, padrões e oferta de cadastro de skills/agentes/comandos existentes), Docs com Markdown da raiz espelhado por link simbólico e execução somente local ou SSH. Sessões de nuvem serão removidas. Ver [requisitos e pendências](07-mudancas-confirmadas.md). Estas são mudanças solicitadas, ainda não implementadas.
