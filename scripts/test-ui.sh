#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="3BABAF15-2ADF-4D42-9EFC-89FF1BE39286"
LOG="build/xcodebuild-test.log"

mkdir -p build

xcodebuild test \
  -project BubbleShooter.xcodeproj \
  -scheme BubbleShooter \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath build/DerivedData \
  -only-testing:BubbleShooterUITests 2>&1 | tee "$LOG" | tail -n 40
exit "${PIPESTATUS[0]}"
