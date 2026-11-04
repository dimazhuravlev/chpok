#!/usr/bin/env bash
# Prints the UDID of the simulator the other scripts run on: $SIM_UDID when
# set, otherwise an available simulator named $SIM_NAME (default
# "iPhone 17 Pro"), a booted one first. Looked up rather than hard-coded:
# simulators get new UDIDs whenever Xcode recreates them.
set -euo pipefail

if [[ -n "${SIM_UDID:-}" ]]; then
  echo "$SIM_UDID"
  exit 0
fi

NAME="${SIM_NAME:-iPhone 17 Pro}"
# Device lines look like "    iPhone 17 Pro (UDID) (Booted)"; the "(" right
# after the name keeps "iPhone 17 Pro Max" out.
DEVICES="$(xcrun simctl list devices available | grep -F "    $NAME (" || true)"
LINE="$(grep -F '(Booted)' <<<"$DEVICES" | head -1 || true)"
if [[ -z "$LINE" ]]; then
  LINE="$(head -1 <<<"$DEVICES")"
fi
UDID="$(sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' <<<"$LINE")"

if [[ ! "$UDID" =~ ^[0-9A-F-]{36}$ ]]; then
  echo "No available simulator named \"$NAME\" (set SIM_UDID or SIM_NAME)" >&2
  exit 1
fi
echo "$UDID"
