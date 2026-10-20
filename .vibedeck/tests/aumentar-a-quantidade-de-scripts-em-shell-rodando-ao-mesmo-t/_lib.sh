# Ajudantes comuns dos scripts deste tópico: checagens estáticas e rápidas, sem rede e sem compilar.
cd "${VIBEDECK_ROOT:-.}"
bad=0
PS=Sources/VibeDeckCore/ProjectStore.swift
RT=Sources/VibeDeckCore/RuleTests.swift
RE=Tests/VibeDeckCoreTests/RuleExecutionTests.swift
RTT=Tests/VibeDeckCoreTests/RuleTestsTests.swift
APPT=Tests/VibeDeckAppTests/RuleExecutionModelTests.swift
MODEL=Sources/VibeDeckApp/RuleExecutionModel.swift
VIEW=Sources/VibeDeckApp/RuleExecutionView.swift
SETTINGS=Sources/VibeDeckApp/AppSettingsView.swift
CLI=Sources/vibedeck/CLI.swift
MCP=Sources/vibedeck/MCPServer.swift
# has FILE REGEX MSG: a regex (ERE) precisa aparecer no arquivo.
has() { grep -Eq -e "$2" "$1" 2>/dev/null || { echo "$1: $3"; bad=1; }; }
# hasF FILE TEXT MSG: o texto literal precisa aparecer no arquivo.
hasF() { grep -Fq -e "$2" "$1" 2>/dev/null || { echo "$1: $3"; bad=1; }; }
# none FILE REGEX MSG: a regex não pode aparecer.
none() { local m; if m=$(grep -nE -e "$2" "$1" 2>/dev/null); then echo "$1: $3"; echo "$m"; bad=1; fi; }
# lineof FILE REGEX [AFTER]: primeira linha (depois de AFTER) que casa; vazio se nenhuma.
lineof() { RE_="$2" awk -v a="${3:-0}" 'NR>a && $0 ~ ENVIRON["RE_"] {print NR; exit}' "$1"; }
# before FILE REGEX_A REGEX_B MSG: A aparece, B aparece e A vem antes de B.
before() {
  local a b; a=$(lineof "$1" "$2"); b=$(lineof "$1" "$3")
  if [ -z "$a" ] || [ -z "$b" ] || [ "$a" -ge "$b" ]; then echo "$1: $4 (linhas ${a:-?} / ${b:-?})"; bad=1; fi
}
finish() { exit $bad; }
