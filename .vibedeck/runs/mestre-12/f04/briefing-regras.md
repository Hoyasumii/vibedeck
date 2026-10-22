# Reconciliação das regras com o Core Rust (decisão D14 do usuário, 2026-10-22)

O Core, CLI e MCP saíram de Swift (`Sources/VibeDeckCore`, `Sources/vibedeck`) para Rust (`crates/vibedeck-core`, `crates/vibedeck`). O app SwiftUI continua em `Sources/VibeDeckApp` e passa a falar com o Core Rust via MCP (`Sources/VibeDeckApp/Core/`). Regras ativas cujos scripts leem o Swift removido precisam ser **reescritas para o Rust**.

## Para cada regra afetada (o script em `.vibedeck/tests/<tópico>/<id8>.sh|.py` referencia código Swift do Core/CLI)
1. Leia a regra (`.vibedeck/rules/<tópico>.json`: `text`, `details`, `test`) e o script.
2. Ache o equivalente no Rust (grep em `crates/`). Reescreva `text`/`details` para o Rust mantendo a **intenção** (ex.: "Toda escrita passa por AtomicFile.write" → "Toda escrita de registro passa por store::write_atomic"). Preserve `id`, `severity`, `group`, `author` e `createdAt`.
3. Reescreva o script para verificar o código Rust, com a mesma semântica de saída: 0 = pass, 77 = não se aplica aos arquivos de `$VIBEDECK_FILES` (vazio = verificar tudo), outro = fail com mensagem útil. Rode na raiz com `VIBEDECK_FILES=""` e confirme **pass** no código atual; se falhar, investigue: é bug do Rust? Relate (não corrija crates/). Confirme também `na` (77) para um arquivo fora do escopo, quando a regra tem escopo.
4. Atualize `test.ruleHash` = primeiros 16 hex de SHA-256(text + "\n" + details) e `test.generatedAt` (ISO-8601 UTC sem fração). Mantenha `mode: script` e `command`.
5. Atualize `paths` do tópico se apontavam para `Sources/VibeDeckCore/**` ou `Sources/vibedeck/**` (para `crates/**` correspondentes).
6. Sem equivalente possível no Rust (detalhe exclusivamente Swift do Core antigo)? Torne o script `exit 77` com comentário explicando, e diga na nota da regra (`details`) "Não se aplica ao Core Rust: <motivo>" — só nesses casos; liste-os no retorno.

Regras sobre o **app** (`Sources/VibeDeckApp`) não são deste trabalho, exceto se o script ler o Core Swift removido.

## Formato
Grave os JSON exatamente como o VibeDeck: `json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False, separators=(',', ' : ')) + "\n"` (confira que um arquivo não alterado faz round-trip idêntico antes de editar). Não edite `.vibedeck/checks/` nem `AGENTS.md`/`guide.md`.

## Pronto quando
Todos os scripts dos seus tópicos rodam com `VIBEDECK_FILES=""` na raiz e dão pass (ou 77 justificado), e `cd worker && npm run validate` continua passando. Sem Git.
