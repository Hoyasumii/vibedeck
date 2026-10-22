---
author: ai
---
# 10 — Atualização automática

Estado: **pedido confirmado pelo usuário em 22/10/2026 (MUD-004) e adiado: fica fora da primeira versão do VibeDeck**, por decisão do usuário no mesmo dia. O mecanismo, os requisitos e o fluxo abaixo são proposta da IA para uma versão posterior. Nada foi implementado nem deve ser implementado na primeira versão.

## MUD-004 — Pedido confirmado (versão posterior)

O app deve ter uma ferramenta de atualização automática: detectar versões novas, baixar, validar e instalar com o mínimo de ação do usuário, sem perder dados nem trabalho em andamento.

## Situação atual observada

- `scripts/build-app.sh` gera `build/VibeDeck.app` e `build/VibeDeck-<versão>.dmg` localmente.
- A assinatura é **ad-hoc** (`codesign --sign -`): sem Developer ID, sem hardened runtime, sem notarização. Um app baixado assim é bloqueado pelo Gatekeeper e cada nova build troca a identidade de código, o que pode invalidar permissões concedidas pelo macOS e itens do Keychain.
- Versão: `CFBundleShortVersionString` vem de `Sources/vibedeck/CLI.swift`; `CFBundleVersion` é um carimbo de data/hora.
- O CLI vai embutido em `Contents/Helpers/vibedeck`; `--install-cli` cria um link em `~/.local/bin` apontando para `build/`, não para o app instalado.
- Não existe pipeline de release, canal de distribuição público, feed de versões nem código de atualização. CI atual só roda `swift test` e o deploy do Worker.

## O que é preciso para funcionar

### 1. Identidade e confiança (pré-requisito bloqueante)

| Item | Para quê |
| --- | --- |
| Conta Apple Developer Program (pago, anual) | Emitir o certificado de distribuição fora da App Store |
| Certificado **Developer ID Application** | Assinatura estável entre versões; Gatekeeper aceita o app |
| Hardened runtime + entitlements mínimos | Exigido pela notarização |
| Notarização (`xcrun notarytool`) + `stapler staple` | App abre sem alerta, inclusive offline |
| Credencial de notarização em CI (API key do App Store Connect) | Automatizar o release |

Sem isso, nenhuma atualização automática no macOS é confiável. A Mac App Store não é recomendada: exige sandbox, incompatível com o app iniciar CLIs, providers, terminal e SSH.

### 2. Mecanismo de atualização do app macOS

**Recomendação: Sparkle 2** (framework padrão de fato para apps macOS fora da App Store, integra por SwiftPM).

- Assinatura **EdDSA (ed25519)** de cada pacote: chave pública em `SUPublicEDKey` no `Info.plist`; chave privada só em segredo do CI e cópia de segurança offline. **Perder a chave privada impede atualizar os usuários existentes.**
- Feed `appcast.xml` em HTTPS (`SUFeedURL`), com versão, notas, tamanho, assinatura e versão mínima do macOS.
- Embutir `Sparkle.framework` em `Contents/Frameworks` com rpath `@executable_path/../Frameworks` (hoje o script só copia executáveis e bundles).
- `CFBundleVersion` estritamente crescente e `CFBundleShortVersionString` em SemVer, de uma única fonte de versão.
- Pacote de atualização: `.zip` ou `.dmg` assinado e notarizado; atualizações delta opcionais.

Alternativa descartável: updater próprio. Só se houver motivo forte, porque teria de reimplementar verificação de assinatura, substituição atômica do bundle, relançamento e recuperação.

### 3. Hospedagem

Proposta: **GitHub Releases** para os binários e o `appcast.xml` servido por domínio estável (GitHub Pages, ou o Cloudflare já usado pelo Worker/R2). A URL do feed precisa durar enquanto houver instalações antigas; trocar de URL exige uma versão de transição que aponte para o novo feed.

### 4. Pipeline de release (CI)

Workflow disparado por tag `vX.Y.Z` em runner macOS:

1. Validar que a tag bate com a fonte de versão.
2. `swift test` (e, durante a migração, testes Rust).
3. Build release universal (arm64 + x86_64, conforme DEC-002).
4. Montar o bundle com Sparkle e o CLI embutido; assinar com Developer ID e hardened runtime, de dentro para fora (helpers e frameworks antes do app).
5. Notarizar, aguardar resultado e grampear (`staple`) o app e o DMG.
6. Gerar o pacote de atualização e assiná-lo (`sign_update` / `generate_appcast`).
7. Publicar release com notas e atualizar o appcast **por último**, só depois de todos os artefatos estarem disponíveis.

Segredos: certificado `.p12` + senha, API key de notarização, chave privada EdDSA. Nunca em repositório, logs ou documentação.

### 5. Experiência no app

- Menu “Verificar atualizações…” e preferência para verificar automaticamente / baixar automaticamente.
- Verificação ao abrir e periodicamente; mostrar notas da versão antes de instalar.
- **Não instalar nem relançar com trabalho ativo**: workflow run em andamento, chat/provider respondendo, terminal ou sessão SSH aberta, edição não salva. Adiar e oferecer instalar ao encerrar.
- Canais `estável` e `beta` (proposta; decidir).
- Falha de download/validação não altera a instalação atual e informa o motivo.

### 6. CLI e MCP

- O CLI embutido no app é atualizado junto com ele. O instalador de CLI deve apontar para `/Applications/VibeDeck.app/Contents/Helpers/vibedeck` (o app instalado), não para `build/`, para acompanhar a atualização.
- Processos MCP stdio já abertos por clientes continuam com o binário antigo até reiniciarem. Definir aviso de versão (stderr ou campo informativo), **nunca escrever em stdout** fora do protocolo.
- Binários Rust independentes (outras máquinas, Linux, hosts SSH): proposta de `vibedeck self-update` lendo um manifesto do mesmo release, com verificação de SHA-256 e assinatura ed25519, substituição atômica e preservação da versão anterior. Nunca se autoatualizar durante uma sessão MCP. Alternativa ou complemento: Homebrew tap.
- SSH: o app deve comparar versão/protocolo do Core remoto com a sua e oferecer atualizar o binário remoto, sem substituir silenciosamente.

### 7. Dados e compatibilidade entre versões

- Versionar o formato dos dados de `.vibedeck/` e migrar para frente de forma idempotente, com cópia de segurança antes de migração destrutiva.
- Uma versão antiga que encontre dados mais novos deve recusar escrita com mensagem clara, não corromper.
- Rollback: manter releases anteriores baixáveis e documentar o retorno manual; Sparkle não faz rollback automático.
- Quando este canal existir, qualquer mudança de Core ou de formato de dados chegará por ele, portanto exige migração de dados e compatibilidade verificadas **antes** de entrar no appcast estável.

### 8. Windows/Linux

Fora desta entrega enquanto DEC-015 estiver aberta. Para CLI/MCP nessas plataformas vale o item 6.

## Decisões pendentes

| ID | Decisão | Recomendação |
| --- | --- | --- |
| UPD-001 | Conta Apple Developer e titularidade (pessoa ou empresa) | Necessária; definir antes do primeiro release público |
| UPD-002 | Mecanismo do app | Sparkle 2 |
| UPD-003 | Hospedagem dos binários e do feed | GitHub Releases + feed em domínio estável |
| UPD-004 | Canais (estável/beta) | Começar com estável; beta opcional |
| UPD-005 | Padrão: só verificar ou baixar e instalar sozinho | Verificar e baixar sozinho; instalar com confirmação |
| UPD-006 | Atualização de CLI/MCP fora do app | `self-update` assinado; Homebrew depois |
| UPD-007 | Versão mínima do macOS | Manter `LSMinimumSystemVersion` atual (26.0) salvo decisão |
| UPD-008 | Fonte única de versão (Swift hoje, Cargo depois) | Um arquivo/tag lido por app, CLI e Core |

## Aceite candidato

- Com a versão N instalada a partir do DMG notarizado e N+1 publicada, o app detecta, mostra notas, baixa, valida a assinatura EdDSA e relança em N+1 sem alerta do Gatekeeper.
- Pacote com assinatura inválida ou corrompido é recusado e N continua funcionando.
- Com workflow run ativo, a instalação é adiada até o fim ou confirmação explícita.
- Depois da atualização, `vibedeck --version` (via link instalado) reporta N+1; dados do projeto abrem e preservam IDs, autoria e relações.
- Com rede indisponível ou feed fora do ar, o app funciona normalmente e reporta a falha só na verificação manual.
- `vibedeck self-update` (quando existir) recusa binário sem assinatura válida e não altera a instalação.
