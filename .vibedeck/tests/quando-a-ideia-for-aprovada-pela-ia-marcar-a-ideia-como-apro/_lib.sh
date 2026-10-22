# Helpers do tópico quando-a-ideia-for-aprovada-pela-ia-marcar-a-ideia-como-apro (use com `source`).
# A decisão do status a partir do veredito (RuleDiscoverVerdict.apply) mora no código de domínio do app
# (Sources/VibeDeckApp/Core/Discover); o Core Rust grava a ideia (ideas.rs) e embute o guia (guide_reference.md).
cd "${VIBEDECK_ROOT:-.}"
LOGIC=Sources/VibeDeckApp/Core/Discover/RuleDiscoverLogic.swift
RULES=Sources/VibeDeckApp/Core/Model/Rules.swift
RD=Sources/VibeDeckApp/RuleDiscover.swift
IDEAV=Sources/VibeDeckApp/IdeaView.swift
TESTS=Tests/VibeDeckAppTests/RuleDiscoverVerdictTests.swift
GUIDE=crates/vibedeck-core/src/ai/guide_reference.md
SCOPE='^Sources/VibeDeckApp/(Core/Discover/RuleDiscoverLogic|Core/Model/Rules|Core/Model/AgentsGuide|RuleDiscover|IdeaView)\.swift$|^Tests/VibeDeckAppTests/RuleDiscoverVerdictTests\.swift$|^crates/vibedeck-core/src/(ideas\.rs|ai/guide_reference\.md)$|^README\.md$|^\.vibedeck/guide\.md$'
fail=0
applies() {
  [ -z "${VIBEDECK_FILES:-}" ] && return 0
  printf '%s\n' "$VIBEDECK_FILES" | grep -E "$SCOPE" >/dev/null || exit 77
}
bad() { echo "$1"; fail=1; }
for f in "$LOGIC" "$RULES" "$RD" "$IDEAV" "$TESTS" "$GUIDE"; do [ -f "$f" ] || { echo "$f: arquivo ausente"; exit 1; }; done

# apply_body: corpo de RuleDiscoverVerdict.apply(to idea:), até a chave que fecha no mesmo recuo.
apply_body() { awk '/func apply\(to idea: inout Idea/{f=1} f{print} f&&/^    }$/{exit}' "$LOGIC"; }
# readiness_body: corpo de RuleDiscoverVerdict.readiness(for:).
readiness_body() { awk '/func readiness\(for idea: Idea/{f=1} f{print} f&&/^    }$/{exit}' "$LOGIC"; }
# has_test <nome>...: confere que o teste existe no arquivo de testes do app (rodam no CI macOS: swift test).
has_test() { local n; for n in "$@"; do grep -qE "func ${n}\(" "$TESTS" || bad "$TESTS: teste '${n}' não existe"; done; }
# require_apply: a regra de aprovação em apply(to:) tem de estar completa.
require_apply() {
  local b; b=$(apply_body)
  [ -n "$b" ] || { bad "$LOGIC: RuleDiscoverVerdict.apply(to:) não encontrado"; return; }
  grep -q 'idea.readiness = readiness' <<<"$b" || bad "$LOGIC: apply deve gravar o readiness na ideia"
  grep -q 'readiness.viable' <<<"$b" || bad "$LOGIC: a aprovação deve depender de readiness.viable"
  grep -q '!idea.status.isClosed' <<<"$b" || bad "$LOGIC: ideia discarded/done não pode mudar de status"
  grep -q 'idea.promotedTopic == nil' <<<"$b" || bad "$LOGIC: ideia já promovida não pode mudar de status"
  grep -q 'idea.status = .approved' <<<"$b" || bad "$LOGIC: apply deve marcar a ideia como approved"
  grep -qE 'viable && !idea\.rules\.isEmpty' <<<"$(readiness_body)" || bad "$LOGIC: readiness.viable exige veredito viável e ideia com regras"
}
finish() { [ $fail -eq 0 ] || exit 1; exit 0; }
