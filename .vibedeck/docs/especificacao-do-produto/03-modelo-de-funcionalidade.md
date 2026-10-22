---
author: ai
---
# Exemplo preenchido e modelo de funcionalidade

Estado: proposta da IA para revisão. As 12 áreas preenchidas estão em [funcionalidades](02-inventario-de-funcionalidades.md).

## Exemplo concreto: registrar check de regras

**ID:** FUN-004. **Natureza:** comportamento atual observado; destino a revisar.
**Objetivo:** conferir regras aplicáveis e registrar evidência da tarefa.
**Ator:** usuário/IA pelo app, CLI ou MCP.
**Entradas:** tarefa, arquivos afetados, tópicos explícitos e revisão opcional.
**Pré-condição:** projeto válido e regras disponíveis.
**Fluxo:** consultar rules_for → executar submit_rule_check → avaliar falhas/avisos → corrigir e reenviar se necessário.
**Saída:** check persistido com resultados por regra e resumo de aprovação/falhas/avisos.
**Estados relevantes:** scripts atuais executam; manuais ficam pending no modo automático. Verificação manual é uma ação explícita.
**Erros:** script não inicia, esgota tempo ou retorna falha; teste desatualizado não é aprovado silenciosamente.
**Limites:** must em falha bloqueia; should em falha avisa. Histórico não é reescrito para transformar reprovação em aprovação.
**Aceite candidato:** com uma regra must que falha, passed é false; depois de corrigir e registrar novo check, o histórico anterior permanece.
**Mudança já desejada:** executar verificações selecionadas por biblioteca/runner Rust.
**Pendente:** destino de scripts arbitrários, manuais, formato de diagnósticos e declaração de recursos compartilhados.
**Evidência:** [runner](../../../Sources/VibeDeckCore/RuleTests.swift), [gate](../../../Sources/VibeDeckCore/StopGate.swift), [fluxo detalhado](funcionalidades/04-regras-checks-e-hooks.md).
O exemplo não aprova essa funcionalidade como desenho final e não representa teste rodado nesta tarefa.

## Modelo reutilizável para uma nova funcionalidade

- Nome/ID e estado da revisão humana.
- Problema, público e objetivo observável.
- Natureza: atual observado, mudança desejada, proposta ou pendência.
- Entradas, campos, defaults, permissões e ferramentas.
- Fluxo principal e resultado persistido.
- Alternativas, erros, cancelamento, timeout e retomada.
- Estados e transições permitidas.
- Regras/invariantes e dados humanos a preservar.
- Diferenças app/CLI/MCP/plataformas.
- Exemplo completo de entrada/ação/saída.
- Critérios de aceite verificáveis.
- Evidências atuais e divergências.
- Decisões humanas e limites do escopo.

O modelo permanece como estrutura de autoria; os campos não preenchidos em novas funcionalidades são pendências explícitas, sem inferir aprovação.
