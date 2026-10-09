#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
need $PW 'SidebarItem\.graph' "a barra lateral não oferece o item Grafo"
need $PW 'case \.graph:' "o detalhe não abre GraphView para .graph"
need $PW 'openInNewTabButton\(\.graph\)' "Grafo não abre em nova aba"
need $PM 'case graph' "SidebarItem.graph ausente"
need $PM 'case \.graph: "graph"' "storageKey de .graph ausente (restauração de abas)"
need $PM 'key == "graph"' "init(storageKey:) não restaura .graph"
need $PM 'case \.graph: "Grafo"' "título da aba Grafo ausente"
need $G 'WKWebView' "a visualização HTML não usa WKWebView"
need $G 'model\.store\.root.*graphify-out|appending\(path: "graphify-out"\)' "o artefato não é lido da raiz do projeto ativo"
exit $fail
