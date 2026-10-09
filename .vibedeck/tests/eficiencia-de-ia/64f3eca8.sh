#!/usr/bin/env bash
set -euo pipefail
exec bash scripts/test-ai-efficiency.sh 'AIRecoveryTests.*(invalidAnswer|persistentFailure)'
