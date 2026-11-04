#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="$(scripts/sim-udid.sh)"
LOG="build/xcodebuild-build.log"

mkdir -p build

xcodegen generate --quiet

set +e
xcodebuild \
  -project BubbleShooter.xcodeproj \
  -scheme BubbleShooter \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath build/DerivedData \
  build > "$LOG" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
  tail -n 5 "$LOG"
else
  tail -n 80 "$LOG"
  exit 1
fi

APP="$(pwd)/build/DerivedData/Build/Products/Debug-iphonesimulator/BubbleShooter.app"
echo "APP=${APP}"
