#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
applies "$SCOPE"
# Pergunta de modo restrita ao app: CLI e MCP sem a nova escolha
for d in "$CLI_DIR" "$MCP_DIR"; do
  for f in $(find "$d" -name '*.rs'); do
    none "$f" 'ideaRequest|IdeaRequest|ChatIntent|intent_prompt|intentPrompt|intent_schema|requestIdeaImplementation|IdeaImplementationSheet|implement_idea_run|choose_mode|implementation_mode' "CLI/MCP não devem usar o fluxo de escolha de modo do app"
  done
done
# start_run do Core não depende da elegibilidade/modo da ideia.
sr=$(awk '/^pub fn start_run\(/{f=1} f{print} f&&/^}/{exit}' "$WFOPS")
[ -n "$sr" ] || { echo "$WFOPS: start_run não encontrado no Core"; bad=1; }
if grep -nE 'is_eligible|IdeaImplementation|implementable_idea|ChatIntent' <<<"$sr"; then echo "$WFOPS: start_run do Core passou a depender do modo/elegibilidade da ideia"; bad=1; fi
# CLI e MCP continuam chamando start_run diretamente.
grep -rq 'wf::start_run(' "$MCP_DIR/tools/workflows.rs" || grep -rqE 'start_run\(' "$MCP_DIR/tools/workflows.rs" || { echo "$MCP_DIR/tools/workflows.rs: workflow_run_start deve chamar start_run"; bad=1; }
grep -rqE 'start_run\(' "$CLI_DIR/workflows.rs" || { echo "$CLI_DIR/workflows.rs: runs start deve chamar start_run"; bad=1; }
# O modo é app-only: os tipos de sessão/folha ficam no app (nenhum no Core Rust).
if grep -rnE 'IdeaImplementationSheet|ideaRequest' crates --include=*.rs; then echo "folha/pedido de modo não pode estar no Core Rust"; bad=1; fi
finish
