---
author: ai
---
# Critérios de aceite e cenários

Estado: **cenários candidatos para revisão humana**. Derivados do comportamento atual e das metas registradas. Não foram executados nesta tarefa e não representam aprovação de implementação.

## Critérios das funcionalidades atuais — revisar o que manter

| ID | Dado / quando | Resultado esperado candidato | Área |
| --- | --- | --- | --- |
| AC-001 | Criar um registro e reler por outra interface | Mesmo ID/conteúdo; escrita sem arquivo parcial | FUN-001 |
| AC-002 | Ideia muda após avaliação | Readiness antiga não permite iniciar como se fosse atual | FUN-002 |
| AC-003 | Dependência pendente ou tentativa de ciclo | Implementação bloqueada antes de promover/criar run; ciclo não grava | FUN-002 |
| AC-004 | Revisão exige regras e não tem check válido | Agente não conclui done; apresenta pendências | FUN-003 |
| AC-005 | Resolver é cancelado antes do aceite | Nenhuma implementação ou exclusão de item | FUN-003 |
| AC-006 | Scripts retornam 0, 77 e falha | pass, na e fail respectivamente; must falhando reprova | FUN-004 |
| AC-007 | Há manual sem pedido de verificação | Fica pending, sem inventar evidência | FUN-004 |
| AC-008 | Regra muda ou script trava | Teste não é reutilizado como atual; timeout/cancelamento termina o trabalho conforme contrato | FUN-004 |
| AC-009 | Workflow interrompe após checkpoint | Retomar preserva saída, etapa, provider e respostas | FUN-005 |
| AC-010 | Workflow atinge limites | Encerra/aguarda ação explícita, sem laço infinito | FUN-005 |
| AC-011 | Kit adicionado novamente ou proposta descartada | Sem sobrescrever cópia anterior; descarte não cria item | FUN-006 |
| AC-012 | Doc é movido/editado externamente | Identidade/referências/anexos coerentes; app reflete mudança | FUN-007 |
| AC-013 | Modelo explícito indisponível | Erro claro; sem troca automática de modelo/provider | FUN-008 |
| AC-014 | Cliente conecta e chama MCP | Resposta válida e stdout sem logs misturados | FUN-009 |
| AC-015 | SSH encontra conflito | Preserva versões e bloqueia IA/regras até decisão; terminal disponível | FUN-010 |
| AC-016 | Padrão é cadastrado | Tópico correspondente consultável; tags não alteram escopo | FUN-011 |
| AC-017 | Consulta de logs/métricas | Sem conteúdo de documentos/prompts/segredos | FUN-011 |
| AC-018 | Geração de grafo falha/cancela | Resultado anterior preservado | FUN-012 |

Cada linha deve ganhar exemplos reais, fixtures e teste específico na implementação. Se você mudar o comportamento, atualizar a linha e a decisão correspondente.

## Aceite da migração

**Etapa 01:** decisões mínimas fechadas; mapa de dependências, contratos e plano de distribuição. Pendências realmente bloqueantes identificadas.
**Etapa 02:** artefato pré-compilado inicia sem UI/toolchains em ambiente limpo; cliente negocia MCP stdio, lista ferramentas e executa leitura/escrita num projeto temporário. Repetir no ambiente SSH escolhido e declarar ferramentas ainda não migradas.
**Etapa 03:** 3 a 5 regras têm paridade pass/fail/na, erros, diagnóstico e cancelamento; comandos antigos recuperáveis. Não exige converter todos os scripts.
**Etapa 04:** contratos mantidos ou alterações explicitamente aprovadas; Core/CLI/MCP integrados e app funcionando; retirar código antigo só após paridade; CLI instalado e empacotamento atualizados.
**Etapa 05:** linha de base, metodologia e resultados antes/depois, sem confundir correção de regressão com otimização opcional.

## Como demonstrar os objetivos humanos

| Objetivo descrito por você | Medição proposta, ainda a aprovar |
| --- | --- |
| Poucos tokens e aprovação de primeira | Amostra comparável de tarefas, tokens informados, tentativas e critérios de aprovação |
| Usuário pouco técnico desenvolve projeto | Jornada acompanhada, tarefas concluídas e intervenções necessárias |
| Funcionalidades funcionam como deveriam | Cenários revisados pelo usuário + testes e evidências dos resultados |
| Instalar em outras máquinas sem muita coisa | Ambiente limpo, lista real de pré-requisitos e passos até primeira chamada MCP |
| Melhor manutenção | Mudanças representativas com domínio compartilhado, sem duplicação e com regressões cobertas |

Não há meta numérica aprovada. Economia não deve ser medida apenas por tokens ignorando falhas, tempo e retrabalho.

## Limites desta coleta

Foi feita leitura de fontes e checagem dos documentos. Não se executou smoke de provider, interface gráfica, SSH ou teste de paridade Rust; esses resultados ainda precisam ser produzidos nas etapas apropriadas. Sessões de nuvem saíram do destino por decisão do usuário.
Os checks de regras desta edição validam o trabalho documental e não provam que todos os cenários do produto estão implementados corretamente.

Referências: [áreas e evidências](02-inventario-de-funcionalidades.md), [contratos](04-contratos-e-compatibilidade.md), [decisões](06-decisoes-e-migracao.md).

## Decisão do usuário — 22/10/2026

O produto passa a ter início guiado (stack, padrões e oferta de cadastro de skills/agentes/comandos existentes), Docs com Markdown da raiz espelhado por link simbólico e execução somente local ou SSH. Sessões de nuvem serão removidas. Ver [requisitos e pendências](07-mudancas-confirmadas.md). Estas são mudanças solicitadas, ainda não implementadas.

### Cenários candidatos das mudanças solicitadas

- AC-019: ao começar projeto, o usuário recebe perguntas sobre stack e padrões; recursos existentes são apresentados para escolha de cadastro, sem importação automática.
- AC-020: recusar o cadastro de skills/agentes/comandos não cria itens nem altera os existentes.
- AC-021: README.md da raiz aparece em Docs por symlink; mudanças na origem aparecem no espelho, sem cópia independente. Remover vínculo conserva a origem (comportamento proposto para revisão).
- AC-022: se edição do vínculo for habilitada, grava na origem e preserva o symlink; links quebrados e colisões têm tratamento explícito a definir.
- AC-023: não há ação de iniciar sessão de nuvem; local e SSH continuam disponíveis. A retirada de comandos/configurações segue transição documentada.
