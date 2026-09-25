#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="$(grep -m1 'DEVELOPMENT_TEAM' project.yml | awk '{print $2}')"
LOG="build/xcodebuild-archive.log"
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ARCHIVE_PATH="${ARCHIVE_DIR}/Chpok-$(date +%Y%m%d-%H%M%S).xcarchive"

mkdir -p build
mkdir -p "$ARCHIVE_DIR"

xcodegen generate --quiet

set +e
xcodebuild archive \
  -project BubbleShooter.xcodeproj \
  -scheme BubbleShooter \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" > "$LOG" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
  tail -n 5 "$LOG"
else
  tail -n 80 "$LOG"
  exit 1
fi

echo "ARCHIVE=${ARCHIVE_PATH}"
echo "Next: open Xcode -> Window -> Organizer -> Archives, select the archive, and click Distribute App."
