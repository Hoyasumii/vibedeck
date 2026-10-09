#!/usr/bin/env bash
set -euo pipefail
bash scripts/test-ai-efficiency.sh 'AIEfficiencyTests.*(guideReduces|catalogPaginates|ruleCheckSummary|compactRulesFor|sharedPolicy)'
exec bash scripts/test-ai-efficiency.sh mcp
