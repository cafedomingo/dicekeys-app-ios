#!/usr/bin/env bash
# Walks every screen of the app in light and then dark appearance and saves a screenshot of
# each into the given folder as NN-screen-light.png / NN-screen-dark.png. The appearance is
# set before each run because the Simulator ignores a change made while a UI test runs, and
# the app is reinstalled with a clean keychain so both runs start from the same state.
#
# Usage: scripts/screen-walk.sh <output-folder> [simulator-udid]
set -euo pipefail

usage="usage: scripts/screen-walk.sh <output-folder> [simulator-udid]"
mkdir -p "${1:?$usage}"
out="$(cd "$1" && pwd)"
# `xcode-select` may point at the Command Line Tools, which ship no xcodebuild.
if [[ -z "${DEVELOPER_DIR:-}" && ! -x "$(xcode-select -p 2>/dev/null)/usr/bin/xcodebuild" ]]; then
  XCODE_APP="$(printf '%s\n' /Applications/Xcode*.app | sort -V | tail -1)"
  [[ -d "$XCODE_APP" ]] || { echo "No Xcode found in /Applications; set DEVELOPER_DIR." >&2; exit 1; }
  export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
fi
command -v xcodegen >/dev/null || { echo "xcodegen is not installed (brew install xcodegen)." >&2; exit 1; }

udid="${2:-$(xcrun simctl list devices booted | grep -Eo '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1 || true)}"
if [ -z "$udid" ]; then
  echo "No booted simulator; boot one or pass its UDID." >&2
  exit 1
fi
xcrun simctl bootstatus "$udid" -b >/dev/null

cd "$(dirname "$0")/.."
xcodegen generate --quiet
bundle_id="$(xcodebuild -showBuildSettings -project DiceKeys.xcodeproj -scheme DiceKeys 2>/dev/null |
  awk '/ PRODUCT_BUNDLE_IDENTIFIER =/ { print $3; exit }')"

for mode in light dark; do
  xcrun simctl uninstall "$udid" "$bundle_id" || true
  xcrun simctl keychain "$udid" reset
  xcrun simctl ui "$udid" appearance "$mode"
  TEST_RUNNER_SHOT_DIR="$out" TEST_RUNNER_SHOT_MODE="$mode" xcodebuild test \
    -project DiceKeys.xcodeproj -scheme DiceKeysScreenWalk \
    -destination "platform=iOS Simulator,id=$udid" \
    CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= -quiet
done
echo "Screenshots in $out"
