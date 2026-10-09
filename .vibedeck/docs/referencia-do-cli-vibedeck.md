---
author: ai
---
# Referência do CLI vibedeck

Fontes: `README.md:243-289`, `README.md:291-340`, `README.md:35-82`.

O CLI `vibedeck` e o servidor MCP (`vibedeck mcp`) expõem as operações do Core. O CLI é instalado em `~/.local/bin/vibedeck` pelo `scripts/build-app.sh --install-cli` (`scripts/build-app.sh:99-103`).

## Revisões

```sh
vibedeck status
vibedeck review list --status open --json
vibedeck review add "Tela" "Esconder link" --kind hide --file src/Login.tsx --ai
vibedeck review set <id-ou-prefixo> --status done
```

(`README.md:246-249`). Para itens ligados a regras, `done` exige check aprovado; humanos usam `--force` (`README.md:107-108`).

## Regras e testes

```sh
vibedeck rules new "Interface" --path "Sources/VibeDeckApp/**"
vibedeck rules add interface "Nunca usar minWidth no root da janela"
vibedeck rules for <arquivo> --json
vibedeck rules check --task "..." --item <id>
vibedeck rules test <arquivo>
vibedeck rules set-test <regra> --command .vibedeck/tests/geral/ab12cd34.sh
```

(`README.md:250-255`). `--manual` solicita a verificação manual (`README.md:89-91`).

## Hook Stop

`vibedeck hook install` liga o hook; `--scope project` versiona em `.claude/settings.json`; `--agent codex` grava `.codex/hooks.json` e precisa ser aprovado com `/hooks` no Codex. `--max-blocks` limita bloqueios seguidos (3 por padrão). `vibedeck hook` mostra onde está ligado (`README.md:109-114`).

## Ideias

```sh
vibedeck ideas new "Modo offline" --tags futuro
vibedeck ideas promote modo-offline
vibedeck ideas unpromote modo-offline
```

(`README.md:258-259`).

## Agentes, comandos, skills, workflows e execuções

- `vibedeck agents|commands|skills import | next | flow` (`README.md:260-269`).
- `vibedeck workflows new | step | route | visits | show | flow` (`README.md:270-277`).
- `vibedeck runs start | next | step | record | questions | answer | show | list` (`README.md:278-282`).
- `vibedeck tag <tipo> <slug> <tags...>`, para doc, review, rules, idea, agent, command, skill, workflow, stack e pattern (`README.md:283`).

## Stack e padrões

- `vibedeck stack` com `search`, `add`, `remove`, `note`, `move` e `badge [--sync]` (`README.md:46-54`).
- `vibedeck patterns` com `catalog`, `add`, `note`, `paths` e `remove` (`README.md:71-79`).

## Integrações

- `vibedeck mcp install` registra o MCP no Claude Code (`--scope local/project/user`) (`README.md:284`). Para Codex: `--provider codex`, gravando `.codex/config.toml` ou `~/.codex/config.toml` com `--scope user` (`README.md:297-299`).
- `vibedeck usage install | usage | usage record` para os limites de uso (`README.md:285-286`, `README.md:330-335`).
- `vibedeck cloud check | start` (`README.md:287-288`). `--allow-dirty` confirma alterações não commitadas (`README.md:324`).
- `vibedeck graph export` gera a visualização offline, sem consumir IA (`README.md:186-187`).
- `vibedeck docs cat` e `vibedeck docs new "Título" --body "..." --ai` (`README.md:174`).
- `vibedeck ai guide [--section n]`, `ai catalog <tipo>`, `ai context <id> --offset --limit` e `ai usage --json [--clear]` (`README.md:358-364`, `README.md:375-376`).

## Provedor Codex nos comandos

Vários comandos aceitam `--provider codex`, por exemplo `agents import`, `commands import`, `skills import`, `runs start` e `usage` (`README.md:300-307`).