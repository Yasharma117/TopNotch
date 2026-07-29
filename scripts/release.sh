#!/bin/bash
#
# Build, Developer-ID sign, notarize, and staple TopNotch for distribution.
#
# One-time setup (see scripts/README-release.md):
#   1. Create a "Developer ID Application" certificate in Xcode.
#   2. Generate an App Store Connect API key (.p8, Key ID, Issuer ID).
#   3. Store notary credentials once:
#        xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#          --key /path/to/AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
#
# Then just run:  ./scripts/release.sh
#
set -euo pipefail

# ---- Config ----------------------------------------------------------------
PROJECT="TopNotch.xcodeproj"
SCHEME="TopNotch"
CONFIG="Release"
NOTARY_PROFILE="${NOTARY_PROFILE:-TopNotchNotary}"   # keychain profile name from store-credentials
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/TopNotch.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="scripts/ExportOptions.plist"
APP="$EXPORT_DIR/TopNotch.app"
UPLOAD_ZIP="$BUILD_DIR/TopNotch-upload.zip"          # sent to Apple's notary service
DIST_ZIP="$BUILD_DIR/TopNotch.zip"                   # final, stapled, for users

# Run from repo root regardless of where invoked.
cd "$(dirname "$0")/.."

echo "==> Preconditions"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "ERROR: No 'Developer ID Application' certificate found in the keychain." >&2
  echo "       Create one in Xcode > Settings > Accounts > Manage Certificates." >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "ERROR: Notary profile '$NOTARY_PROFILE' not found." >&2
  echo "       Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --key <p8> --key-id <id> --issuer <id>" >&2
  exit 1
fi

echo "==> 1/6 Clean + archive ($CONFIG)"
rm -rf "$BUILD_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" clean archive

echo "==> 2/6 Export with Developer ID (hardened runtime)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" -exportPath "$EXPORT_DIR"

echo "==> 3/6 Zip for notarization"
ditto -c -k --keepParent "$APP" "$UPLOAD_ZIP"

echo "==> 4/6 Submit to Apple notary service (waits for result)"
xcrun notarytool submit "$UPLOAD_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> 5/6 Staple the ticket to the app"
xcrun stapler staple "$APP"

echo "==> 6/6 Verify (Gatekeeper + stapled ticket)"
spctl -a -vvv -t exec "$APP"
xcrun stapler validate "$APP"

echo "==> Packaging final distributable"
ditto -c -k --keepParent "$APP" "$DIST_ZIP"

echo ""
echo "Done. Notarized, stapled app: $APP"
echo "Distribute this: $DIST_ZIP"
