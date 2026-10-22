#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 103B84BC: referências (nextSteps/etapas) só apontam para itens do kit adicionado; dependências ausentes impedem a adição.
need "$KITS" 'pub fn missing_dependencies' "validação de dependências ausente"
need "$KITS" 'MissingKitDependencies\(missing\)' "instalação deve rejeitar dependências pendentes"
need "$KITS" '\.get\(r\)' "referências devem ser remapeadas para os slugs criados"
need "$KITS" 'let missing = missing_dependencies\(refs\)\?;' "add_kit_items deve validar antes de gravar"
need "$VIEW" 'missingDependencies' "UI deve exigir dependências"
# Dados do catálogo: toda referência de etapa aponta para um item do mesmo kit.
python3 - "$ASSETS" <<'P' || fail=1
import json,sys,glob,os
bad=0
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*.json'))):
    d=json.load(open(f)); ids={d['id']+':'+i['kind'] for i in d['items']}
    for i in d['items']:
        for s in i.get('steps',[]):
            if s['ref'] not in ids: print(f"{f}: etapa '{s['id']}' aponta para '{s['ref']}', fora do kit"); bad=1
sys.exit(bad)
P
finish
