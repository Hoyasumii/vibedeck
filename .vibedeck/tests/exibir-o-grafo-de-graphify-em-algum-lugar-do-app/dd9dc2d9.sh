#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
need $G 'nonPersistent' "dados do site não são efêmeros"
need $G 'allowingReadAccessTo: *readAccess' "leitura não restrita a graphify-out/"
forbid $G 'addScriptMessageHandler|evaluateJavaScript|WKScriptMessageHandler' "ponte JS↔app exposta"
# A política de navegação só pode permitir file:// dentro de graphify-out/.
pol=$(sed -n '/decidePolicyFor/,/^        }/p' $G)
printf '%s' "$pol" | grep -qE 'readAccess|hasPrefix|standardized' || bad "$G:1" "decidePolicyFor permite qualquer file URL (fora de graphify-out/) e subframes .other"
grep -qE 'Content-Security-Policy|WKContentRuleList|contentRuleList|WKUserScript' $G || bad "$G:1" "sem CSP/regras de conteúdo bloqueando recursos remotos e script inline não confiável dentro do HTML"
grep -qE 'allowsContentJavaScript *= *false|javaScriptEnabled *= *false' $G || true
exit $fail
