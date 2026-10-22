#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 2621DABD: o catálogo traz os kits de manutenção e de novas ferramentas, cada um com agente, comando, skill e workflow.
python3 - "$ASSETS" <<'P' || fail=1
import json,sys,os
bad=0
for kid in ('manutencao','novas-ferramentas'):
    f=os.path.join(sys.argv[1],kid+'.json')
    d=json.load(open(f))
    if d['id']!=kid: print(f"{f}: id esperado '{kid}', achei '{d['id']}'"); bad=1
    kinds={i['kind'] for i in d['items']}
    for k in ('agent','command','skill','workflow'):
        if k not in kinds: print(f"{f}: falta item do tipo {k}"); bad=1
sys.exit(bad)
P
need "$KITS" 'manutencao\.json' "kit de manutenção não está embutido"
need "$KITS" 'novas-ferramentas\.json' "kit de novas ferramentas não está embutido"
need "$KITS" 'pub const ALL: \[KitItemKind; 4\]' "deve existir a lista dos quatro tipos de item"
finish
