---
author: ai
---
# Inventário de funcionalidades

Estado: levantamento atual para revisão em 22/10/2026. Cada documento descreve o existente e separa direção futura e perguntas. A lista não obriga você a manter todos os recursos.

| ID | Documento | Destino |
| --- | --- | --- |
| FUN-001 | [Projetos e persistência](funcionalidades/01-projetos-e-persistencia.md) | Adicionar início guiado — MUD-001 |
| FUN-002 | [Ideias, avaliação e dependências](funcionalidades/02-ideias-e-dependencias.md) | Atual descrito; destino em revisão |
| FUN-003 | [Revisões e resolução](funcionalidades/03-revisoes-e-resolucao.md) | Atual descrito; destino em revisão |
| FUN-004 | [Regras, checks e hooks](funcionalidades/04-regras-checks-e-hooks.md) | Atual descrito; destino em revisão |
| FUN-005 | [Workflows e execuções](funcionalidades/05-workflows-e-execucoes.md) | Atual descrito; destino em revisão |
| FUN-006 | [Agentes, comandos, skills e kits](funcionalidades/06-agentes-comandos-skills-e-kits.md) | Atual descrito; destino em revisão |
| FUN-007 | [Documentação e referências](funcionalidades/07-docs-links-grupos-e-anexos.md) | Espelhar Markdown da raiz por symlink — MUD-002 |
| FUN-008 | [Provedores, chat e permissões](funcionalidades/08-provedores-chat-e-permissoes.md) | Atual descrito; destino em revisão |
| FUN-009 | [CLI e MCP](funcionalidades/09-cli-e-mcp.md) | Atual descrito; destino em revisão |
| FUN-010 | [Execução local e projetos SSH](funcionalidades/10-nuvem-e-ssh.md) | Remover sessões de nuvem; manter local/SSH — MUD-003 |
| FUN-011 | [Stack, padrões, configuração e diagnóstico](funcionalidades/11-stack-padroes-logs-e-metricas.md) | Atual descrito; destino em revisão |
| FUN-012 | [Interface, navegação e grafo](funcionalidades/12-interface-grafo-e-navegacao.md) | Atual descrito; destino em revisão |

## Como marcar sua decisão

Em cada área, acrescente “manter”, “mudar para”, “retirar” ou “decidir depois”, explicando o resultado desejado. Depois atualizaremos critérios, contratos e ideias afetados.
Não trate ausência de uma funcionalidade nesta lista como decisão de excluí-la. O inventário cobre os recursos identificados nas fontes, não certifica todos os detalhes de execução.

## Recursos transversais incluídos

Autoria humana/IA, identidade por UUID, arquivos versionáveis, busca/tags, grupos, desfazer/refazer, cancelamento, permissões, limites de execução e leitura sob demanda aparecem nos documentos correspondentes.
Stack/padrões e métricas foram reunidos em FUN-011; terminal e grafo em FUN-012; coleção Claude em FUN-007.

## Mapa para as etapas do Core

| Etapa | Áreas prioritárias | Resultado esperado |
| --- | --- | --- |
| 01 Arquitetura | Todas, com foco em FUN-001/004/008/009 | Limites, contratos, decisões e mapa de dependências |
| 02 MCP mínimo | FUN-001/009/010 | Prova de distribuição e leitura/escrita por stdio |
| 03 Regras piloto | FUN-004/009 | Amostra com paridade, diagnóstico e cancelamento |
| 04 Migração | Todas as áreas que você decidir manter | Paridade ou alterações explicitamente aprovadas |
| 05 Desempenho | FUN-001/008/011/012 e cenários relevantes | Medição e melhorias demonstradas |

## Fontes e limites

Coleta em README.md, .vibedeck/guide.md, código Swift e testes selecionados. Cada área contém referências recuperáveis.
Documentos antigos podem estar defasados: por exemplo, descrições antigas de checks exigem vereditos de todas as regras; o fluxo atual executa scripts e deixa manuais pendentes por padrão. A especificação usa o fluxo atual do guia e do código como evidência, deixando mudanças futuras para sua decisão.

## Decisão do usuário — 22/10/2026

O produto passa a ter início guiado (stack, padrões e oferta de cadastro de skills/agentes/comandos existentes), Docs com Markdown da raiz espelhado por link simbólico e execução somente local ou SSH. Sessões de nuvem serão removidas. Ver [requisitos e pendências](07-mudancas-confirmadas.md). Estas são mudanças solicitadas, ainda não implementadas.
