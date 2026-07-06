#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh "${1:-debug}"
open build/ClaudeUsageTracker.app
