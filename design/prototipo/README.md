# Protótipo da interface

Cópia editável do artefato "VibeDeck — Logo e interface multiplataforma" do claude.ai, atualizada com as
funcionalidades atuais e as mudanças confirmadas (início guiado, Docs vinculados, só local e SSH).

- `boards/`: uma prancha por arquivo; `boards.json` define ordem, tamanho e a nota de cada uma.
- `components/`: partes compartilhadas (`V2Rail`, `V2StatusBar`, `Body`, `Sidebar`).
- `vendor/`: biblioteca `VibeDeck.*` do Design System, runtime das pranchas e React.
- `bundler/loader.html`: carregador do HTML único.

Gerar o HTML único (abre via file:// e pode voltar ao claude.ai):

```sh
python3 -I scripts/prototipo/build.py                 # todas as pranchas → design/prototipo/dist/
python3 -I scripts/prototipo/build.py design/prototipo /tmp/p.html --only 37-   # uma prancha
```

Reimportar uma versão nova exportada do claude.ai: `python3 -I scripts/prototipo/extract.py "<arquivo>.html"`
(sobrescreve `boards/`, `components/` e `vendor/`).

O mapa das pranchas, as decisões pendentes e o prompt de implementação estão em
`.vibedeck/docs/especificacao-do-produto/11-prompt-de-implementacao-da-interface.md`.
