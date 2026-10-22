#!/usr/bin/env bash
# Painel mostra o título, indicador de carregamento e erro em pt-BR (didFail/didFailProvisionalNavigation).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies 'Sources/VibeDeckApp/LinksView\.swift'

panel=$(block '^private struct LinkViewerPanel')
need "$panel" 'Text\(link\.title\)' "painel deve mostrar o título do link"
need "$panel" 'else if isLoading \{' "painel deve tratar isLoading"
need "$panel" 'ProgressView\("Carregando página…"\)' "indicador de carregamento em pt-BR"
need "$panel" 'if failed \{' "painel deve tratar a falha"
need "$panel" 'ContentUnavailableView\("Não foi possível carregar a página"' "mensagem de erro em pt-BR"

web=$(block 'struct LinkWebView: NSViewRepresentable')
need "$web" 'didFail navigation: WKNavigation!, withError error: Error\) \{ fail\(error\) \}' "didFail deve marcar a falha"
need "$web" 'didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error\) \{ fail\(error\) \}' "didFailProvisionalNavigation deve marcar a falha"
need "$web" 'didFinish navigation: WKNavigation!' "didFinish deve encerrar o carregamento"
f=$(awk '/private func fail\(_ error: Error\)/{f=1} f{print} f&&/parent.failed = true/{exit}' <<<"$web")
need "$f" 'parent\.isLoading = false' "fail deve encerrar o carregamento"
need "$f" 'parent\.failed = true' "fail deve marcar failed = true"
exit $fail
