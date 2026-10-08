# VibeDeck — guia para agentes de IA

Este diretório é gerenciado pelo app **VibeDeck**. Ele guarda links, documentos,
pontos de revisão, **regras** e **ideias** do projeto em arquivos locais que você (agente) pode ler e editar.

## ⚠️ Regras — obrigatório antes de concluir qualquer tarefa

Nenhuma tarefa está concluída sem passar pelas regras do projeto:

1. Chame `rules_for` (MCP) ou `vibedeck rules for <arquivos> --json` com os arquivos que você
   alterou (e o id do item de revisão, se houver).
2. Verifique cada regra retornada contra o seu trabalho de verdade (leia o código, rode o que precisar).
3. Envie o resultado com `submit_rule_check` (ou `vibedeck rules check`): `pass`, `fail` ou `na`
   para **cada** regra, com uma nota curta de evidência.
4. Se `passed` for `false`, corrija e envie um novo check. Só diga que terminou quando passar.
   Regras `should` que falham não bloqueiam, mas avise o usuário.

Itens de revisão ligados a regras (`rules`, ou `target.file` casando os `paths` de um tópico)
não podem ir para `done` sem um check aprovado para aquele item.

## Estrutura

```
vibedeck.json                 # declara o projeto: nome, links, tipos de revisão (reviewKinds)
.vibedeck/
  AGENTS.md                   # este arquivo (regenerado pelo app; não edite)
  docs/<slug>.md              # documentos markdown (título = frontmatter `title:` ou primeiro `# `)
  reviews/<slug>.json         # um grupo (tema) de itens de revisão por arquivo
  rules/<slug>.json           # um tópico de regras por arquivo (paths = globs de escopo)
  ideas/<slug>.json           # uma ideia por arquivo (brainstorm, com regras rascunho)
  checks/*.json               # verificações de regras registradas (histórico; não edite)
```

Schemas: https://vibedeck-schema.alanreisanjo.workers.dev/v1/{project,review-group,rule-topic,idea,rule-check}.schema.json

## Itens de revisão

Cada item de `reviews/*.json` descreve algo a ajustar no projeto
("inativar esse botão", "isso não precisa aparecer agora"):

- `kind`: um dos `reviewKinds` do vibedeck.json (padrão: disable, hide, fix, change, remove, note)
- `status`: open | in_progress | done | wontfix
- `priority`: low | normal | high
- `target` (opcional): `file`, `route`, `component`, `selector` — onde no código/app
- `author`: human | ai

## Tópicos de regras

- `paths` vazio → o tópico vale para **toda** tarefa; com globs (`Sources/App/**`, `*.swift`) vale
  quando um arquivo alterado casa.
- `rules[].severity`: `must` (bloqueia) | `should` (aviso).
- Você pode propor regras novas (`add_rule`), mas não apague regras de humanos.

## Ideias

Ideias (`ideas/*.json`) são futuras e **não** são regras ativas: `status` new | exploring | approved |
discarded | done, `body` em markdown, `rules` rascunho. `promote_idea` transforma as regras da
ideia em um tópico de regras real (aí passam a valer). Registre ideias que surgirem com `add_idea`.

## Tags

Docs (frontmatter `tags: [a, b]`), grupos de revisão, tópicos de regras e ideias aceitam `tags`.
Use `set_tags` (MCP) ou `vibedeck tag <doc|review|rules|idea> <ref> <tags...>`.

## Regras gerais para agentes

1. Prefira o CLI (`vibedeck ...`) ou o servidor MCP (`vibedeck mcp`) em vez de editar o JSON à mão.
   Se editar à mão, siga o schema e mantenha ids (UUID) e datas ISO 8601.
2. Itens criados por você devem ter `author: "ai"`.
3. Ao começar um item, marque `in_progress`; ao concluir, `done`. Não apague itens de humanos.
4. Antes de mexer em uma área, leia os itens abertos que apontam para ela.

## Comandos úteis

```sh
vibedeck status                              # resumo do projeto
vibedeck review list --status open --json    # itens abertos
vibedeck review add "Tela de login" --kind hide "Esconder link de cadastro" --file src/Login.tsx --ai
vibedeck review set <id> --status done       # id completo ou prefixo (>= 4 chars)
vibedeck docs list | vibedeck docs cat <slug>
vibedeck rules for src/Login.tsx --json      # regras aplicáveis (com ids)
echo '[{"ruleId":"ab12","verdict":"pass","note":"..."}]' | vibedeck rules check --task "..." --file src/Login.tsx --item <id>
vibedeck ideas list | vibedeck ideas new "Modo offline"
```

MCP: `vibedeck mcp install` (registra `vibedeck mcp` no Claude Code)
