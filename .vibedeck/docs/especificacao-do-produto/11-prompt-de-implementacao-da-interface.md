---
author: ai
---
# 11 — Prompt de implementação da nova interface (protótipo)

Estado: protótipo atualizado em 22/10/2026 com as funcionalidades atuais (regras e ideias concluídas) e as mudanças confirmadas MUD-001, MUD-002 e MUD-003. A seção "Decisões antes de implementar" ainda precisa da sua resposta. O prompt abaixo só deve ser usado depois disso.

## Onde está o protótipo

| Caminho | Conteúdo |
| --- | --- |
| `design/prototipo/boards/NN-*.html` | Uma prancha por arquivo, editável. Cabeçalho com os tokens (`:root`, `[data-theme]`) e o CSS dos componentes. |
| `design/prototipo/boards.json` | Ordem, título, tamanho e **nota** de cada prancha (o que mudou e por quê). |
| `design/prototipo/components/*.dc.html` | Partes compartilhadas: `V2Rail` (trilho de espaços), `V2StatusBar` (barra de status com ambiente), `Body` e `Sidebar` (V1). |
| `design/prototipo/vendor/vibedeck-components.js` | Biblioteca `VibeDeck.*` do Design System: ícones (16 px, traço 1.6), Logo, Button, SegmentedControl, FilterChip, badges, SidebarItem, TreeFolder, StepCard, ChatBubble, StackCard, PatternCard e outros. |
| `scripts/prototipo/build.py` | Gera `design/prototipo/dist/<título>.html` (HTML único, abre via file:// e pode voltar ao claude.ai). `--only <trecho>` gera só uma prancha. |
| `scripts/prototipo/extract.py` | Reimporta uma versão nova exportada do artefato do claude.ai. |

Para ver: `python3 -I scripts/prototipo/build.py` e abrir o HTML de `design/prototipo/dist/`.

## Mapa das pranchas

**Alvo (V2, macOS 26):** 13–38. **Referência (V1):** 00–12, usadas para logo, tokens, componentes e conteúdo das telas que a V2 não redesenhou. Windows e Linux (02, 03) ficam fora desta entrega.

| Prancha | Tela | Origem da funcionalidade |
| --- | --- | --- |
| 00 | Logo e ícones | ícone do app (`scripts/make-icon.swift`) |
| 13 | Qualidade › Regras (+ Reorganizar) | regras, checks, botão Reorganizar |
| 14 | Planejar › Ideia (Descubra, dependências) | Descubra, dependência de ideias |
| 15 | Qualidade › Revisão (Resolver) | botão Resolver, Descubra em Onde/Regras |
| 16, 20, 21, 22 | Automação: agente, workflow, comando com terminal, kits | agentes, comandos, skills, workflows, kits, execução de workflow |
| 17, 26 | Projeto: visão geral, grafo | stack, padrões, grafo graphify, integrações |
| 18, 19 | Trilho de espaços; barra de status (Local/SSH/offline/conflito) | navegação V2, MUD-003 |
| 23, 35, 36 | Planejar › Doc; doc vinculado; vincular Markdown da raiz | gerar documentos, MUD-002 |
| 24 | Planejar › Referências | links e coleção do Claude |
| 25 | IA em tela cheia | chat, conversas, providers (sem nuvem) |
| 27 | Ajustes | configurações do app |
| 28, 29, 30 | Boas-vindas; conectar via SSH; projeto SSH em conflito | projetos SSH, MUD-003 |
| 31–34 | Início guiado: stack, padrões, recursos encontrados, resumo | MUD-001 |
| 37 | Ideia › Implementar (workflow ou execução padrão) | executar ideia com workflow, dependências |
| 38 | Qualidade › Reorganizar (proposta) | botão Reorganizar |

## Decisões antes de implementar

1. **V2 como alvo.** Confirmar que a navegação V2 (trilho com Planejar, Automação, Qualidade e Projeto, painel de IA à direita e barra de status) substitui a barra lateral única da V1.
2. **Regras ativas em conflito com a V2.** A ideia "Nova Interface" diz que o protótipo prevalece, mas mudar regras ativas exige ação explícita. Revisar antes de começar:
   - interface-do-app: "Limites de coluna só via navigationSplitViewColumnWidth / inspectorColumnWidth" (047D2216), "Sem faixa de toolbar separada" (492100C1), "Visual nativo do macOS 26" (B382469C), "O accordion da sidebar não depende da seleção" (335DA4F8);
   - dinamicas-da-interface: "A sidebar tem uma seção por conceito, cada uma com lista filtrável" (3901FA3E) e "Detalhe + inspector (⌥⌘I)" (34D2EA32), porque na V2 a coluna da direita é o painel de IA (⇧⌘C);
   - painel-lateral-melhorado e "Listas de seção filtráveis por texto e por #tag" (A999B857): definir onde fica o filtro em cada espaço.
3. **Início guiado (MUD-001):** gatilho (Novo projeto, pasta sem `vibedeck.json` ou primeira abertura), se "Pular por agora" pode ser retomado em Projeto › Visão geral, e quais origens são varridas (`.claude/agents|commands|skills`, `.codex/prompts`).
4. **Docs vinculados (MUD-002):** a prancha 35 propõe que editar grava na origem. Confirmar, ou trocar por leitura apenas. Definir também o tratamento de vínculo quebrado e de colisão de nomes.
5. **Nuvem (MUD-003):** mensagem de transição dos comandos e das configurações removidos.
6. **Ícones novos:** SSH usa `terminal` e vínculo usa `link`, que já existem no Design System. Se quiser ícones próprios (servidor, link simbólico), eles entram em `vibedeck-components.js` e no ícone do app.

## Prompt

```text
Você vai implementar a nova interface do VibeDeck (macOS 26, SwiftUI) seguindo o protótipo em design/prototipo/.
Leia antes: .vibedeck/AGENTS.md, a ideia "Nova Interface" (get_idea nova-interface), este doc (seção Decisões, já respondida),
list_stack, list_patterns, itens de revisão abertos de Sources/VibeDeckApp e rules_for Sources/VibeDeckApp/ProjectWindow.swift.

Fonte da verdade visual:
- Tokens: o bloco ":root / [data-theme]" de qualquer design/prototipo/boards/*.html (cores claro/escuro, --space-*, --radius-*,
  --duration-*, fontes Bricolage Grotesque, SF Pro e JetBrains Mono, escalas display-xl..mono). Exporte-os para um único
  Sources/VibeDeckApp/DesignTokens.swift com grupos de cor, espaçamento, raio, fonte e animação, e uma variante de animação
  nula ou .opacity com accessibilityReduceMotion.
- Componentes: design/prototipo/vendor/vibedeck-components.js (VibeDeck.*) e o CSS "VibeDeck components" das pranchas.
  Crie uma view SwiftUI por componente, com o mesmo nome e as mesmas variantes.
- Telas: as pranchas 13–38 (alvo V2). Leia a nota de cada uma em boards.json. Use 00–12 só como referência.
  Para conferir: python3 -I scripts/prototipo/build.py --only NN- e abra o HTML gerado.

Escopo:
1. DesignTokens.swift e componentes. Nenhuma view usa Color literal, .padding/spacing/cornerRadius/.system(size:) numéricos
   ou durações literais fora de DesignTokens.swift. Crie o script de regra em .vibedeck/tests no tópico da ideia.
2. Janela V2: trilho de espaços (18), navegação por espaço, conteúdo, painel de IA recolhível (⇧⌘C) e barra de status (19),
   com uso de IA, tarefa em andamento, ambiente Local/SSH (offline com pendências, conflito), último check, Terminal e branch.
3. Telas na ordem: Boas-vindas (28) + SSH (29, 30) → Início guiado (31–34) → Planejar (14, 37, 23, 35, 36, 24) →
   Qualidade (13, 38, 15) → Automação (16, 20, 21, 22) → Projeto (17, 26) → IA em tela cheia (25) → Ajustes (27).
4. Remova a interface antiga de uma vez, sem flag nem preferência, e apague as views que ficarem sem uso.
   Remova também a UI de sessões na nuvem (MUD-003).
5. scripts/make-icon.swift gera o ícone a partir do logo da prancha 00, nas cores do Design System.

Preserve: comportamento do Core, CLI e MCP; edição direta com undo; persistência imediata; mudanças externas ao vivo;
LoggedButton/loggedControl nos controles; textos em pt-BR; atalhos documentados; "nada é gravado antes do aceite" nas
propostas da IA; bloqueio de Implementar por dependência pendente; perguntar Workflow/Execução padrão/Cancelar e
Retomar/Reiniciar. Não troque modelo nem provedor. Não promova ideias.

Conclusão: swift test passa; rules_for com os arquivos alterados; submit_rule_check com passed=true; README e
.vibedeck/guide.md atualizados se algo documentado mudou; capturas das telas implementadas comparadas com as pranchas.
Se faltar contexto ou uma decisão, pare e pergunte em vez de inventar.
```
