---
author: ai
---
# Regras de negócio: checks, bloqueios e hook Stop

Fontes: `README.md:84-127`, `.vibedeck/docs/conceitos-do-vibedeck.md` (conceitos base já documentados lá; aqui só os pontos operacionais).

## Severidade e escopo

- `must` bloqueia; `should` só avisa (`README.md:86`).
- Sem `paths`, o tópico vale para toda tarefa; com globs, vale quando um arquivo alterado casa (`README.md:86-87`).

## Fluxo exigido do agente

1. `rules_for` com os arquivos alterados.
2. `submit_rule_check`, que roda os scripts automaticamente. Regras manuais ficam pendentes.
3. Só conclui com `passed=true`.

Use `include_manual` / `verify_manual` (CLI: `--manual`) quando a verificação manual for solicitada, com `pass`/`fail`/`na` e evidência (`README.md:88-92`).

## Testes de regras (scripts)

- "Gerar testes" pede ao provedor que transforme cada regra em `.vibedeck/tests/<tópico>/<regra>.sh`, ou a marque como **manual** (`README.md:92-94`).
- O script roda na raiz do repositório, com `$VIBEDECK_FILES` contendo os arquivos alterados. Código de saída `0` cumpre, `77` não se aplica e outro código viola (`README.md:94-96`).
- Editar o texto ou os detalhes de uma regra deixa o teste **desatualizado**: volta a ser manual, com aviso, até "Atualizar testes" (`README.md:96-97`).
- "Gerar verificações" em lote roda um `claude -p` por tópico, até 3 em paralelo (`README.md:98-100`).

## Executar regras no app

- Modo sem IA: só scripts. Modo com IA: scripts primeiro e depois as regras restantes com o provedor selecionado (`README.md:101-104`).
- Falhas de IA ou regras alteradas durante a execução impedem salvar um check incompleto. Uma verificação completa entra no histórico mesmo com regras reprovadas. Os scripts não rodam de novo ao salvar (`README.md:104-106`).

## Bloqueio de `done`

Item de revisão ligado a regras (campo `rules` ou `target.file` casando um tópico) não vai para `done` via CLI/MCP sem check aprovado para o item. `vibedeck review set --force` é para humanos (`README.md:107-108`).

## Hook Stop

- O agente não encerra a resposta enquanto um arquivo alterado na sessão tiver regras aplicáveis sem check aprovado, registrado depois da alteração e cobrindo todos os tópicos do arquivo (`README.md:109-113`).
- A sessão é detectada pelo git, desde o início do transcript (ou do `SessionStart` no Codex) (`README.md:111-112`).
- Depois de 3 bloqueios seguidos (`--max-blocks`), o hook libera e avisa o usuário, para não prender o agente num laço (`README.md:113-114`).

## Padrões de projeto

Cada padrão em `vibedeck.json` (`patterns`) cria um tópico `.vibedeck/rules/padrao-<nome>.json` com `sourcePattern`. Remover o padrão apaga o tópico, e apagar o tópico retira o padrão (`README.md:67-69`).

## Descubra

- **No item de revisão:** a IA explora só em leitura e propõe **Onde** e tópicos de **Regras**. Arquivos inexistentes e tópicos desconhecidos são descartados. Nada muda até o aceite, que vale um único ⌘Z (`README.md:115-119`).
- **Nas regras:** a IA propõe globs e tags, faz entrevista (até 4 perguntas por rodada, 3 rodadas) e sugere regras `must`/`should`. Globs catch-all (`**`, `*`, `**/*`) ou que não casam arquivos são descartados (`README.md:120-127`).