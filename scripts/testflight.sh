#!/usr/bin/env bash
# Archive and (optionally) upload an app to TestFlight with the Apple ID that is signed in to Xcode.
# Usage: scripts/testflight.sh <ios|mac> <archive|export|upload>
#   archive  build a signed .xcarchive (no upload)
#   export   archive + export an .ipa/.pkg locally (validates signing; no upload)
#   upload   archive + upload to App Store Connect (TestFlight processing starts automatically)
# Requires: paid Apple Developer Program team in Xcode (Settings > Accounts) and the app record in App Store Connect.
# The build number (CURRENT_PROJECT_VERSION in project.yml) must increase with every upload.
set -euo pipefail
cd "$(dirname "$0")/.."
PLATFORM="${1:?ios|mac}"; MODE="${2:?archive|export|upload}"
TEAM_ID="${APPLE_TEAM_ID:-J2DU2P47XW}"
OUT="${OUT_DIR:-$HOME/.cache/timetrack-testflight}"
case "$PLATFORM" in
  ios) SCHEME=TimetrackIOS; DEST='generic/platform=iOS' ;;
  mac) SCHEME=TimetrackMac; DEST='generic/platform=macOS' ;;
  *) echo "platform must be ios or mac" >&2; exit 64 ;;
esac
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
mkdir -p "$OUT"
ARCHIVE="$OUT/$SCHEME.xcarchive"
rm -rf "$ARCHIVE"
xcodebuild archive -project Timetrack.xcodeproj -scheme "$SCHEME" -configuration Release -destination "$DEST" \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" | tail -5
[ "$MODE" = archive ] && { echo "archive: $ARCHIVE"; exit 0; }
DESTINATION=export; [ "$MODE" = upload ] && DESTINATION=upload
PLIST="$OUT/ExportOptions-$MODE.plist"
cat > "$PLIST" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
P
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$PLIST" -exportPath "$OUT/export-$PLATFORM" \
  -allowProvisioningUpdates | tail -8
echo "$MODE done ($OUT)"
