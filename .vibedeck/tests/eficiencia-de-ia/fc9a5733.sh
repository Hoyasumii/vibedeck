#!/usr/bin/env bash
set -euo pipefail
exec bash scripts/test-ai-efficiency.sh 'AIEfficiencyTests.*usageSeparates'
