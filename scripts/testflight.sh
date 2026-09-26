#!/bin/bash
# Archive the iOS app and upload it to TestFlight (App Store Connect).
#
#   scripts/testflight.sh [build-number]        # build number defaults to YYYYMMDDHHMM
#
# Versioning is date-based and computed here, not stored in the repository: the
# marketing version is today's date (2026.9.22, no leading zeros because Apple wants
# plain integers between the periods) and the build number is a minute-resolution
# timestamp. Both always rise, which is what App Store Connect requires, and two uploads
# on the same day differ in the build number.
#
# What this script cannot do for you:
#   1. A PAID Apple Developer Program membership is required. A free "Personal Team"
#      cannot upload to App Store Connect at all: it can only install onto a device
#      you have paired with this Mac, and those builds stop working after seven days.
#   2. Authentication, either of:
#        - Xcode signed in to that account (Xcode > Settings > Accounts > "+"), or
#        - an App Store Connect API key, via the three environment variables
#          ASC_KEY_PATH (the .p8 file), ASC_KEY_ID and ASC_ISSUER_ID. Preferred for
#          automation; create one under Users and Access > Integrations. Put them in a
#          .env file in the repository root (git-ignored; see .env.example) and this
#          script loads it. Keep the .p8 itself outside the repository.
#   3. Config/Signing.local.xcconfig with your DEVELOPMENT_TEAM (see Config/Signing.xcconfig).
#   4. An app record in App Store Connect for the bundle id in Config/Signing.xcconfig,
#      registered to that team.
#
# Internal testers (people on your team) get the build once Apple finishes processing
# it. External testers additionally need App Review.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
    set -a
    # shellcheck source=/dev/null
    source .env
    set +a
fi

# `xcode-select` may point at the Command Line Tools, which ship no xcodebuild.
if [[ -z "${DEVELOPER_DIR:-}" && ! -x "$(xcode-select -p 2>/dev/null)/usr/bin/xcodebuild" ]]; then
    XCODE_APP="$(printf '%s\n' /Applications/Xcode*.app | sort -V | tail -1)"
    [[ -d "$XCODE_APP" ]] || { echo "No Xcode found in /Applications; set DEVELOPER_DIR." >&2; exit 1; }
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
fi

BUILD_NUMBER="${1:-$(date +%Y%m%d%H%M)}"
MARKETING_VERSION="$(date +%Y.%-m.%-d)"
ARCHIVE="build/DiceKeys.xcarchive"
EXPORT_DIR="build/export"

# Expanded as ${AUTH[@]+"${AUTH[@]}"} below: macOS ships bash 3.2, where "${AUTH[@]}" on
# an empty array is an unbound-variable error under `set -u`.
AUTH=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
    : "${ASC_KEY_ID:?ASC_KEY_PATH is set, so ASC_KEY_ID is required}"
    : "${ASC_ISSUER_ID:?ASC_KEY_PATH is set, so ASC_ISSUER_ID is required}"
    AUTH=(-authenticationKeyPath "$ASC_KEY_PATH"
          -authenticationKeyID "$ASC_KEY_ID"
          -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

command -v xcodegen >/dev/null || { echo "xcodegen not installed (brew install xcodegen)" >&2; exit 1; }
grep -q '^DEVELOPMENT_TEAM *= *[A-Z0-9]' Config/Signing.local.xcconfig 2>/dev/null \
    || { echo "Set DEVELOPMENT_TEAM in Config/Signing.local.xcconfig first (see Config/Signing.xcconfig)." >&2; exit 1; }

xcodegen generate
rm -rf "$ARCHIVE" "$EXPORT_DIR"

xcodebuild archive \
    -project DiceKeys.xcodeproj \
    -scheme DiceKeys \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    ${AUTH[@]+"${AUTH[@]}"} \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

mkdir -p build
cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist build/ExportOptions.plist \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates \
    ${AUTH[@]+"${AUTH[@]}"}

echo "Uploaded $MARKETING_VERSION ($BUILD_NUMBER); it reaches TestFlight when Apple finishes processing."
