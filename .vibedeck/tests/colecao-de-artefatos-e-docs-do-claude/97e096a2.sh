#!/usr/bin/env bash
# 97E096A2: a coleção do Claude só recebe o que o usuário adiciona: sem importação automática, sem rede.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies '^crates/vibedeck-core/src/project/claude\.rs$|^crates/vibedeck-core/src/model/project\.rs$|^crates/vibedeck/src/(cli|mcp/tools)/project\.rs$|^Sources/VibeDeckApp/ClaudeItemsView\.swift$'
# Nenhum acesso a rede/processo no módulo da coleção (Rust) nem na view.
forbid "$CORE" 'reqwest|ureq|hyper|TcpStream|std::process|Command::new|tokio::process' "a coleção não pode buscar/importar itens sozinha"
forbid "$VIEW" 'URLSession|URLRequest|Process\(|api\.anthropic|\.data\(from' "a coleção não pode buscar/importar itens sozinha"
# Só estes pontos acrescentam à coleção: claude::add (CLI/MCP, pedido explícito) e o editor do app.
hits=$(grep -rnE 'claude\.push\(' crates --include=*.rs | grep -vE '^crates/vibedeck-core/src/project/claude\.rs' || true)
[ -z "$hits" ] || bad "escrita na coleção fora de claude::add: $hits"
hits=$(grep -rnE '\.claude\.append\(' Sources --include=*.swift | grep -vE '^Sources/VibeDeckApp/(ClaudeItemsView|LinksView)\.swift' || true)
[ -z "$hits" ] || bad "escrita na coleção fora do editor do usuário: $hits"
# Colar um link só abre o editor (não adiciona direto), e o tipo precisa ser escolhido pelo usuário.
grep -A12 'onPasteCommand' "$VIEW" | grep 'editing = ClaudeItem' >/dev/null || bad "$VIEW: colar link deve apenas abrir o editor"
grep -A12 'onPasteCommand' "$VIEW" | grep 'claude.append' >/dev/null && bad "$VIEW: colar link não pode adicionar direto"
grep -q 'kind = isNew ? nil' "$VIEW" || bad "$VIEW: novo item deve começar sem tipo escolhido"
grep -q 'disabled(normalized == nil)' "$VIEW" || bad "$VIEW: Adicionar deve exigir dados válidos"
# CLI e MCP: add exige url e --kind explícitos, e só aceita claude.ai.
a=$(fn_body "$CLI" '^pub enum ClaudeCommand')
grep -qF '#[arg(long, value_parser = ["artifact", "doc"])]
        kind: String,' <<<"$a" || bad "$CLI: claude add: --kind deve ser obrigatório (String, não Option)"
need "$CORE" 'if !accepts\(url\)' "claude::make deve rejeitar URL fora de claude.ai"
need "$CORE" 'host\.eq_ignore_ascii_case\("claude\.ai"\)' "só o host claude.ai é aceito"
need "$MCP" 'args\.req\("kind"\)' "add_claude_item: kind deve ser obrigatório"
need "$MCP" '&\["url", "kind"\]' "add_claude_item: url e kind devem ser required no schema"
finish
