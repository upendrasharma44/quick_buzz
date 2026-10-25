#!/usr/bin/env bash
# Captures App Store / review screenshots from the simulator using DEBUG demo mode.
#
# Usage: scripts/screenshots.sh [simulator name] [output dir]
#   defaults: "iPhone 17 Pro Max" (6.9", 1320×2868) and docs/app-store/screenshots
# Requires: xcodegen, Xcode. Builds a Debug app (demo mode is DEBUG-only) into a temp folder.
set -euo pipefail

SIM="${1:-iPhone 17 Pro Max}"
OUT="${2:-docs/app-store/screenshots}"
BUNDLE=com.upendrasharma.buzzlight
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$(mktemp -d)"
trap 'rm -rf "$DERIVED"' EXIT

cd "$ROOT"
mkdir -p "$OUT"
xcodegen generate -q
xcodebuild build -project BuzzLight.xcodeproj -scheme BuzzLight -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO -quiet

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi
xcrun simctl install "$SIM" "$DERIVED/Build/Products/Debug-iphonesimulator/BuzzLight.app"

# shot <file> <seconds to wait> <launch args...>
shot() {
  local file=$1 wait=$2; shift 2
  xcrun simctl launch --terminate-running-process "$SIM" "$BUNDLE" -profile.name Upendra -BLDemo YES "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$SIM" screenshot "$OUT/$file.png" >/dev/null 2>&1
  echo "captured $OUT/$file.png"
}

# The first launch after install is slow; warm the app up so the timings below hold.
xcrun simctl launch --terminate-running-process "$SIM" "$BUNDLE" -profile.name Upendra -BLDemo YES >/dev/null
sleep 5

# Timings measured on a warm launch with DemoHub.Timing.standard (bots join every 0.7 s, rounds
# arm 2 s after idle, bots react in 0.25–1.2 s, results stay up 4 s):
#   host:   round 1 results ≈ 5–9 s, round 2 results ≈ 12–16 s
#   player: round 1 armed ≈ 2.5 s, results ≈ 3.5–7.5 s
shot 1-host-results      7   -BLRoute host -BLDemoAutoPlay YES
shot 2-player-winner     5   -BLRoute join-first -BLDemoAutoBuzz fast
shot 3-player-live       4.5 -BLRoute join-first
shot 4-host-scores      13   -BLRoute host -BLDemoAutoPlay YES
shot 5-join-list         2   -BLRoute join
shot 6-player-too-early  4.5 -BLRoute join-first -BLDemoAutoBuzz early

xcrun simctl status_bar "$SIM" clear
