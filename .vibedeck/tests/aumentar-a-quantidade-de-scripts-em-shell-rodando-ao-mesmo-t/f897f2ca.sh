#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
a=$(lineof $VIEW 'if execution\.active \{')
b=$(lineof $VIEW 'LoggedButton\("Cancelar"')
{ [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && [ $((b - a)) -le 3 ]; } || { echo "$VIEW: o botão Cancelar deve ficar dentro de if execution.active (linhas ${a:-?}/${b:-?})"; bad=1; }
hasF $VIEW 'execution.cancel()' "o botão deve chamar execution.cancel()"
finish
