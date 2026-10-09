---
author: ai
---
# Sessões na nuvem e limites de uso

Fontes: `README.md:316-340`, `.github/workflows/swift.yml:23-29`.

## Sessões na nuvem

- Acionadas pelo botão de nuvem no painel IA, por `vibedeck cloud start` ou pela tool MCP `start_cloud_session` (`README.md:318-319`).
- Claude usa `claude --cloud`. Codex usa `codex cloud exec --env <ambiente> --branch <branch>` (`README.md:319-321`).
- O ID do ambiente Codex Cloud pode ficar em `codexCloudEnvironment` no projeto ou ser passado com `--env` (`README.md:321-322`).
- Antes de iniciar, o VibeDeck faz `git fetch` e compara a branch padrão local com a da `origin`. Se uma estiver atrás da outra ou se divergirem, ele para e avisa (`README.md:322-324`).
- Alterações não commitadas geram só um aviso, confirmado com `--allow-dirty` / `allow_dirty` (`README.md:324`).
- `vibedeck cloud check` verifica se a main local é igual à do GitHub (`README.md:287`).
- O projeto traz um `.mcp.json` com o servidor `vibedeck mcp`. O binário precisa estar no `PATH` da VM Linux (`README.md:326`). O CI garante que o CLI compila em Linux (`.github/workflows/swift.yml:23-29`).

## Limites de uso do Claude Code

- O rodapé da sidebar mostra o uso da sessão (5h) e da semana, e quando cada uma reinicia (`README.md:330-331`).
- Os dados vêm da statusline: `vibedeck usage install` faz ela rodar `vibedeck usage record`, que grava em `~/Library/Application Support/VibeDeck/claude-usage.json` (`README.md:331-333`).
- Uma statusline anterior continua aparecendo (`--then`), e `vibedeck usage uninstall` a devolve (`README.md:333-334`).
- Só funciona com login de assinatura (Pro/Max). Com chave de API, o Claude Code não informa limites (`README.md:334-335`).
- A tool MCP `claude_usage` dá aos agentes o mesmo dado (`README.md:335`).

## Limites do Codex

Com Codex selecionado, o rodapé consulta os limites direto no App Server. `codex_usage` oferece os mesmos dados via MCP, e contas sem limites mostram a indisponibilidade (`README.md:337-339`). Hooks novos do Codex precisam ser aprovados com `/hooks` no terminal do Codex (`README.md:339-340`).

## Codex: MCP e importações

- `vibedeck mcp install --provider codex` grava `.codex/config.toml` do projeto, ou `~/.codex/config.toml` com `--scope user` (`README.md:297-298`).
- O instalador inclui o adaptador de compatibilidade com o SDK Swift MCP 0.12 e exige Python 3. `--force` substitui apenas registro gerenciado pelo VibeDeck (`README.md:309-310`).
- Arquivos inválidos de importação são reportados, e registros existentes são preservados salvo `--overwrite` (`README.md:313`).