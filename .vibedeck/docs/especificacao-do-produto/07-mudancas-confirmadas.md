---
author: ai
---
# 07 — Mudanças confirmadas: início guiado, Docs vinculados e local/SSH

# Mudanças confirmadas pelo usuário — 22/10/2026

Estado: requisitos de produto solicitados pelo usuário, ainda não implementados. Esta decisão substitui as metas anteriores de sessões de nuvem. Detalhes indicados como proposta ou pendência continuam abertos.

## MUD-001 — Início guiado de um projeto

**Pedido confirmado:** quem estiver começando um projeto no VibeDeck deve ser guiado por perguntas sobre stack e padrões. Quando já existirem skills, agentes e comandos no projeto, perguntar se o usuário deseja cadastrá-los no VibeDeck.

### Fluxo proposto para realizar o pedido

1. Ao iniciar/configurar um projeto, explicar o objetivo da preparação e perguntar quais tecnologias compõem a stack.
2. Perguntar quais padrões de projeto o usuário quer adotar, oferecendo os recursos de catálogo existentes.
3. Detectar skills, agentes e comandos presentes nas origens suportadas do projeto e apresentar o que foi encontrado.
4. Perguntar se deseja cadastrar/importar os itens encontrados; permitir revisar a seleção antes de confirmar.
5. Mostrar resumo do que será registrado e aplicar a escolha. Não importar nem sobrescrever automaticamente itens por terem sido detectados.
6. Encaminhar para a organização do projeto com stack, padrões e recursos selecionados disponíveis para humano e IA.

A obrigação de perguntar é confirmada; a apresentação em passos e o resumo são proposta de UX.
**Pendências:** gatilho exato (inicialização, primeira abertura ou ambos), possibilidade de pular/retomar, fontes/escopos de descoberta e comportamento diante de itens duplicados. Definir o mesmo destino no contexto local e SSH sem assumir importação de recursos do Mac para o servidor.

**Aceite candidato:** projeto recém-iniciado recebe perguntas de stack/padrões; se houver recursos suportados, o usuário vê quais são e pode aceitar/recusar o cadastro. Recusar não cria registros. Recursos já cadastrados não são duplicados silenciosamente.

## MUD-002 — Markdown da raiz espelhado em Docs por link simbólico

**Pedido confirmado:** a seção Docs deve espelhar arquivos Markdown da raiz do projeto, como README.md, usando links simbólicos. O arquivo da raiz continua sendo a fonte do conteúdo; o espelho não é uma cópia independente.

### Comportamento proposto

- Permitir selecionar arquivos .md da raiz para aparecerem em Docs.
- Criar links simbólicos apropriados em .vibedeck/docs/ apontando para os arquivos escolhidos da raiz, preferencialmente com destinos relativos para manter portabilidade.
- Mostrar o conteúdo atual do arquivo de origem e refletir alterações feitas fora do app.
- Distinguir visualmente um documento vinculado de um documento armazenado diretamente em Docs.
- Ao remover o espelho, remover apenas o vínculo, preservando README.md e os demais arquivos de origem.

A seleção, sinalização visual e remoção apenas do vínculo são propostas para tornar o espelhamento previsível.
**Pendências:** link automático ou por seleção; leitura apenas ou edição que grava na origem; link quebrado, origem renomeada/movida e colisão de nomes; como Git, Windows e SSH representam esses links; política para caminhos fora do projeto.
A validação atual de caminhos gerenciados precisa ser revisada deliberadamente: um link de Docs para a raiz está fora de docs/ mas dentro do projeto. Não liberar genericamente qualquer symlink ou trocar a gravação atômica sem preservar a origem/vínculo. Se houver edição, a implementação deverá gravar o destino sem substituir o link por arquivo comum.

**Aceite candidato:** README.md aparece em Docs sem segunda cópia de conteúdo; alteração na origem aparece no espelho; remover o espelho conserva a origem. Se edição for habilitada, editar pelo Docs atualiza a origem e o link continua sendo link.

## MUD-003 — Somente local e SSH; remover sessões de nuvem

**Pedido confirmado:** remover a funcionalidade de sessões de nuvem do VibeDeck. Os ambientes de execução do produto passam a ser local e SSH.

### Consequências de escopo

- Retirar o fluxo de iniciar sessões de nuvem, seus botões, comandos, ferramentas MCP e configurações específicas.
- Inventariar cloud start/check, start_cloud_session/cloud_check e configurações como codexCloudEnvironment antes da remoção; definir a transição de comandos e dados antigos.
- Preservar chat, providers, workflows, regras, terminal e MCP para os modos local e SSH.
- MCP por stdio e distribuição multiplataforma continuam na direção do Core Rust. Isso não implica hospedar um serviço MCP HTTP.
- Serviços de IA usados pelos providers não são a feature de “sessão de nuvem” do VibeDeck. Remover essa feature não exige transformar Claude/Codex em modelos offline.
- A etapa 02 do Core valida máquina limpa/local e ambiente SSH, substituindo o teste em sessão de nuvem.
- Revogar requisitos anteriores que exigiam sessões de nuvem; descrições históricas servem apenas ao inventário da remoção.

**Pendências:** mensagem/compatibilidade de comandos removidos, destino de configurações/históricos antigos e momento da remoção na migração. Não apagar dados antigos nesta tarefa de anotação.

**Aceite candidato:** produto não oferece nem inicia sessão de nuvem; fluxos local e SSH permanecem funcionais; CLI/MCP deixam de expor criação de sessões de nuvem segundo a política de transição escolhida.

## Relação com a especificação e as ideias

MUD-001: FUN-001, FUN-006 e FUN-011.
MUD-002: FUN-007 e contratos de arquivos, leitura/escrita e grupos.
MUD-003: FUN-009/FUN-010, contratos, aceite e ideias 01–05 do Core.
A ordem das cinco etapas permanece; muda o destino da prova MCP. Onboarding e Docs entram no mapa de funcionalidades da migração, com prioridade interna a definir.

Antes de implementar, reconciliar as regras ativas e os rascunhos com essas decisões. Em especial, o rascunho 13D1425F-0210-42DD-B667-A24FFDA86743 da reescrita exigia nuvem e está revogado por esta decisão; não deve ser promovido assim. A ferramenta atual de atualização de ideias não edita regras individuais: a revisão desse texto estruturado fica explicitamente pendente antes da promoção/implementação. As demais exigências de paridade devem tratar a remoção de nuvem como exceção deliberada do usuário.
