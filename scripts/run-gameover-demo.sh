#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="82760CFF-E851-48E3-8909-A2541FCB87D3"
BUNDLE_ID="com.dimazhuravlev.BubbleShooter"
APP="$(pwd)/build/DerivedData/Build/Products/Debug-iphonesimulator/BubbleShooter.app"

if [ ! -d "$APP" ]; then
  ./scripts/build.sh
fi

xcrun simctl bootstatus "$UDID" -b

open -a Simulator --args -CurrentDeviceUDID "$UDID"

xcrun simctl install "$UDID" "$APP"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

xcrun simctl launch "$UDID" "$BUNDLE_ID" -showGameOverDemo

sleep 4

mkdir -p build/screenshots

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SCREENSHOT="$(pwd)/build/screenshots/${TIMESTAMP}.png"

xcrun simctl io "$UDID" screenshot "$SCREENSHOT"

echo "SCREENSHOT=${SCREENSHOT}"
