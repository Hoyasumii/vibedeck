#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
# V2: Grafo é uma página de Projeto (lista da coluna de conteúdo) que abre GraphView no detalhe e em nova aba.
need $NAV 'case \.graph' "a navegação V2 não oferece a página Grafo"
need $NAV 'case \.project: return \[[^]]*\.graph' "Projeto não lista Grafo"
need $PW 'case \.graph:' "o detalhe não abre GraphView para .graph"
need $PW 'GraphView\(\)' "o detalhe de .graph não mostra GraphView"
need $COL 'Abrir em Nova Aba' "páginas do Projeto (Grafo) sem Abrir em Nova Aba"
need $PM 'case graph' "SidebarItem.graph ausente"
need $PM 'case \.graph: "graph"' "storageKey de .graph ausente (restauração de abas)"
need $PM 'key == "graph"' "init(storageKey:) não restaura .graph"
need $PM 'case \.graph: "Grafo"' "título da aba Grafo ausente"
need $G 'WKWebView' "a visualização HTML não usa WKWebView"
need $G 'model\.store\.root.*graphify-out|appending\(path: "graphify-out"\)' "o artefato não é lido da raiz do projeto ativo"
exit $fail
