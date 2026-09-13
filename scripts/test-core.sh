#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

cd Packages/BubbleShooterCore
swift test 2>&1 | tail -n 30
exit "${PIPESTATUS[0]}"
