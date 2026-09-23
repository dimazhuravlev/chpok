#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="82760CFF-E851-48E3-8909-A2541FCB87D3"
LOG="build/xcodebuild-test.log"

mkdir -p build

xcodebuild test \
  -project BubbleShooter.xcodeproj \
  -scheme BubbleShooter \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath build/DerivedData \
  -only-testing:BubbleShooterUITests 2>&1 | tee "$LOG" | tail -n 40
exit "${PIPESTATUS[0]}"
