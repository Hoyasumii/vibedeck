#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
hasF $PS 'state.results[index] = run' "o resultado deve ser gravado na posição de declaração"
hasF $PS 'state.results.compactMap { $0 }' "o retorno deve seguir a ordem de declaração"
has $RE 'func resultsInDeclarationOrderWithOneEventPairPerRule' "falta o teste de ordem dos resultados"
hasF $RE 'runs.map(\.command) == ["slow", "a", "b", "c", "d"]' "o teste deve comparar a ordem com a primeira regra mais lenta"
has $RE 'func runRuleTestsPreservesTopicAndRuleOrder' "falta o teste de ordem tópico/regra de runRuleTests"
finish
