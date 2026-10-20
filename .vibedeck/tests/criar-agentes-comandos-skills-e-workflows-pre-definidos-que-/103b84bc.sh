#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
applies
need "$CAT" 'missingDependencies' "validação de dependências ausente"
need "$INST" 'missingKitDependencies' "instalação deve rejeitar dependências pendentes"
need "$INST" 'mapping\[ref\]' "referências devem ser remapeadas para slugs criados"
need "$VIEW" 'missingDependencies' "UI deve exigir dependências"
need "$CORET" 'item\.dependencies\.allSatisfy' "teste de dependências do kit ausente"
need "$CORET" 'missingKitDependencies\(workflow\.dependencies\)' "teste de workflow isolado ausente"
need "$CORET" 'isolatedPromptsHaveNoPendingReferences' "teste de item isolado ausente"
need "$CORET" 'step\.transitions\.allSatisfy' "teste de transições ausente"
finish
