#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="3BABAF15-2ADF-4D42-9EFC-89FF1BE39286"
BUNDLE_ID="com.dimazhuravlev.BubbleShooter"
APP="${1:-$(pwd)/build/DerivedData/Build/Products/Debug-iphonesimulator/BubbleShooter.app}"

xcrun simctl bootstatus "$UDID" -b

open -a Simulator --args -CurrentDeviceUDID "$UDID"

xcrun simctl install "$UDID" "$APP"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

xcrun simctl launch "$UDID" "$BUNDLE_ID"

sleep 4

mkdir -p build/screenshots

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SCREENSHOT="$(pwd)/build/screenshots/${TIMESTAMP}.png"

xcrun simctl io "$UDID" screenshot "$SCREENSHOT"

echo "SCREENSHOT=${SCREENSHOT}"
