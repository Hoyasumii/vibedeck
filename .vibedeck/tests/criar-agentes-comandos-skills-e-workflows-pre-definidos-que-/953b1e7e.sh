#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
# 953B1E7E: itens adicionados são ordinários (editáveis à mão e por IA), sem vínculo que bloqueie edição.
forbid "$KITS" 'read_?only|locked|immutable|is_locked' "itens do catálogo não podem ser bloqueados"
need "$KITS" 'tags: vec!\["kit"\.into\(\)\]' "instalação deve marcar apenas com tag ordinária"
forbid "$PMODEL" 'catalog.*(revert|restore|reset)|(revert|reset).*[Kk]it' "catálogo não deve reverter edições"
forbid "$KITS" 'revert|restore|reset' "instalação não deve restaurar/reverter edições"
# Registros instalados usam o mesmo tipo e o mesmo update dos demais.
need "$KITS" 'persona::update::<Agent>' "item instalado deve ser atualizável como qualquer agente"
need "$KITS" 'author,' "autor (human/ai) deve ser repassado, como nos itens criados à mão"
finish
