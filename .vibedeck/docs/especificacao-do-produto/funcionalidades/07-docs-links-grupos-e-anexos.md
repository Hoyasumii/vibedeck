---
author: ai
---
# FUN-007 — Documentação e referências

# FUN-007 — Documentação e referências

Estado: levantamento do produto atual em 22/10/2026, para revisão do usuário. Descrever o existente não decide preservá-lo na nova versão.

## Comportamento atual observado

Docs são Markdown legível por humano e IA; edição tem modos editar/dividir/ler, autosave e desfazer. Links do projeto têm título, URL e tags, com visualizador HTTP/HTTPS ou navegador.
Ideias, docs, revisões e skills admitem diretórios aninhados. Referências completas desambiguam slugs. Movimentos preservam identidade e ajustam referências necessárias; exclusão de grupo não vazio exige confirmação. Anexos podem ser associados a docs/ideias.
Geração de documentos e reorganização assistida produzem propostas somente leitura antes do aceite. A coleção Claude guarda links curados para artefatos/docs; remover da coleção não apaga nada na conta externa.

## Fluxo de uso

1. Registrar ou gerar proposta de documento/link.
2. Revisar e aceitar; organizar em grupo e tags.
3. Consultar pelo app, CLI ou MCP.
4. Reorganizar por proposta selecionada, mantendo histórico/identidade conforme a operação.

## Regras e limites atuais a revisar

Docs são contexto, não regras ativas. Visualizar links não escreve no projeto. A coleção não importa itens sozinha. Caminhos inseguros, saídas da raiz e destinos que sobrescrevam itens são recusados.

## Direção desejada já registrada

Documentação compartilhada entre usuário e IA é parte central confirmada. A especificação do produto passa a ser referência explícita das ideias do Core.

## Decisões para o usuário

Revisar se manter coleção Claude como conceito próprio, visualizador interno, anexos, tags, geração e reorganização; decidir como versionar uma especificação revisada.

## Cenário de aceite proposto

AC-007: editar doc pelo MCP aparece no app; mover documento conserva anexos resolvíveis; descartar proposta não cria arquivos.
Este cenário é candidato à especificação final; não foi executado como teste nesta tarefa documental.

## Evidências recuperáveis

- [Sources/VibeDeckCore/ProjectStore.swift](../../../../Sources/VibeDeckCore/ProjectStore.swift)
- [Sources/VibeDeckCore/ItemGroups.swift](../../../../Sources/VibeDeckCore/ItemGroups.swift)
- [Sources/VibeDeckCore/DocGenerate.swift](../../../../Sources/VibeDeckCore/DocGenerate.swift)
- [.vibedeck/guide.md](../../../../.vibedeck/guide.md)
- [README.md](../../../../README.md)

As evidências descrevem o estado inspecionado; reler os trechos relevantes ao implementar. Guia atual: [regras e operações](../../../guide.md). Voltar ao [inventário](../02-inventario-de-funcionalidades.md).

## Mudança confirmada — MUD-002: Markdown da raiz por symlink

Docs deve espelhar arquivos Markdown da raiz, por exemplo README.md, via link simbólico, mantendo a origem como fonte única do conteúdo.
Definir se links são criados por seleção ou descoberta automática e se a edição pelo Docs grava na origem. Como proposta, remover o espelho deve remover apenas o link. Revisar links quebrados, nomes repetidos, caminhos relativos, escrita atômica, Windows e SSH.
A validação atual de caminhos de Docs precisa acomodar conscientemente a raiz do projeto sem permitir destinos arbitrários. Ver [registro da decisão](../07-mudancas-confirmadas.md). Pedido ainda não implementado.
