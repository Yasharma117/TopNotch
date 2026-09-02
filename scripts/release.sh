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
DMG_STAGE="$BUILD_DIR/dmg"                           # only the .app goes in the install window
DIST_DMG="$BUILD_DIR/TopNotch.dmg"                   # final, stapled, for users

# Run from repo root regardless of where invoked.
cd "$(dirname "$0")/.."

echo "==> Preconditions"
SIGN_ID="$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' | head -1)"
if [ -z "$SIGN_ID" ]; then
  echo "ERROR: No 'Developer ID Application' certificate found in the keychain." >&2
  echo "       Create one in Xcode > Settings > Accounts > Manage Certificates." >&2
  exit 1
fi
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "ERROR: create-dmg not found (needed to build the install window)." >&2
  echo "       Run: brew install create-dmg" >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "ERROR: Notary profile '$NOTARY_PROFILE' not found." >&2
  echo "       Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --key <p8> --key-id <id> --issuer <id>" >&2
  exit 1
fi

echo "==> 1/8 Clean + archive ($CONFIG)"
rm -rf "$BUILD_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" clean archive

echo "==> 2/8 Export with Developer ID (hardened runtime)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" -exportPath "$EXPORT_DIR"

echo "==> 3/8 Zip for notarization"
ditto -c -k --keepParent "$APP" "$UPLOAD_ZIP"

echo "==> 4/8 Submit to Apple notary service (waits for result)"
xcrun notarytool submit "$UPLOAD_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> 5/8 Staple the ticket to the app"
xcrun stapler staple "$APP"

echo "==> 6/8 Verify (Gatekeeper + stapled ticket)"
spctl -a -vvv -t exec "$APP"
xcrun stapler validate "$APP"

echo "==> 7/8 Build the .dmg install window"
# $EXPORT_DIR also holds DistributionSummary.plist / ExportOptions.plist /
# Packaging.log; stage the app alone so they don't show up in the window.
rm -rf "$DMG_STAGE" "$DIST_DMG"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
create-dmg \
  --volname "TopNotch" \
  --codesign "$SIGN_ID" \
  --background "scripts/dmg-background.tiff" \
  --window-size 540 380 \
  --icon-size 110 \
  --icon "TopNotch.app" 140 190 \
  --app-drop-link 400 190 \
  "$DIST_DMG" "$DMG_STAGE" || true
# ponytail: create-dmg exits non-zero on a benign AppleScript hiccup while still
# writing a good dmg, so trust the artifact, not the exit code. Tighten to a
# real status check if it ever starts failing silently.
if [ ! -f "$DIST_DMG" ]; then
  echo "ERROR: create-dmg produced no $DIST_DMG" >&2
  exit 1
fi

echo "==> 8/8 Notarize + staple the .dmg"
# The app inside is already stapled; stapling the dmg itself is what makes the
# very first open clean when the user is offline.
xcrun notarytool submit "$DIST_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DIST_DMG"
xcrun stapler validate "$DIST_DMG"
spctl -a -vvv -t install "$DIST_DMG"

echo "==> Packaging the .zip too (kept for existing links)"
ditto -c -k --keepParent "$APP" "$DIST_ZIP"

echo ""
echo "Done. Notarized, stapled app: $APP"
echo "Distribute this: $DIST_DMG"
echo "Also built:      $DIST_ZIP"
