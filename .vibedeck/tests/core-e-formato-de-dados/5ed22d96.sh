#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# init(from:) só exige (try c.decode) os campos essenciais; o resto é decodeIfPresent ?? default.
applies '(^|/)Sources/VibeDeckCore/'
grep -q 'func lenientHandWrittenTopicAndIdea(' Tests/VibeDeckCoreTests/RulesTests.swift || { echo "Tests/VibeDeckCoreTests/RulesTests.swift: teste de referência lenientHandWrittenTopicAndIdea sumiu"; exit 1; }
python3 -I - <<'PY'
import glob, re, sys
# Campos essenciais por modelo. Chave nova obrigatória deve virar decodeIfPresent com default.
ESSENTIAL = {"title", "name", "url", "text",            # modelos principais
             "ref", "to", "step", "question", "workflow", "number",  # referências de workflow/execução
             "topic", "ruleId", "verdict", "id", "icon",  # resposta/resultado de regra, catálogos
             "usedPercentage"}                          # JSON externo de uso do Claude
bad = 0
req = re.compile(r'try\s+\w+\.decode\([^)]*,\s*forKey:\s*\.(\w+)\)')
for f in sorted(glob.glob("Sources/VibeDeckCore/*.swift")):
    for n, l in enumerate(open(f).read().split("\n"), 1):
        m = req.search(l)
        if m and m.group(1) not in ESSENTIAL:
            print(f"{f}:{n}: '{m.group(1)}' é obrigatório; use decodeIfPresent ?? default: {l.strip()}"); bad += 1
sys.exit(1 if bad else 0)
PY
