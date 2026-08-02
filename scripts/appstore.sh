#!/bin/bash
#
# Archive, sign (Apple Distribution), and upload TopNotch to App Store Connect.
#
# This is a DIFFERENT path from release.sh (which does Developer ID + notarize
# for distribution OUTSIDE the store). Use this one only for Mac App Store.
#
# Prerequisites (see scripts/README-release.md):
#   1. An app record for com.yashsharma.TopNotch exists in App Store Connect.
#   2. scripts/asc-credentials.local.sh exists (git-ignored) and exports:
#        ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH   (App Store Connect API key)
#      The key needs a role that can upload builds (App Manager, or Developer).
#   3. You're signed into the Apple ID (team 8B8KZZ8HVU) in Xcode so automatic
#      signing can create the Apple Distribution cert + App Store profile.
#
# Then:  ./scripts/appstore.sh
#
set -euo pipefail

PROJECT="TopNotch.xcodeproj"
SCHEME="TopNotch"
CONFIG="Release"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/TopNotch-appstore.xcarchive"
EXPORT_DIR="$BUILD_DIR/appstore-export"
EXPORT_PLIST="scripts/ExportOptions-AppStore.plist"

cd "$(dirname "$0")/.."

# Load API-key credentials (git-ignored; never committed).
CREDS="scripts/asc-credentials.local.sh"
if [[ -f "$CREDS" ]]; then
  # shellcheck disable=SC1090
  source "$CREDS"
fi
: "${ASC_KEY_ID:?Set ASC_KEY_ID (in $CREDS)}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID (in $CREDS)}"
: "${ASC_KEY_PATH:?Set ASC_KEY_PATH to your AuthKey .p8 (in $CREDS)}"
[[ -f "$ASC_KEY_PATH" ]] || { echo "ERROR: key not found at $ASC_KEY_PATH" >&2; exit 1; }

echo "==> 1/2 Clean + archive ($CONFIG)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  clean archive

echo "==> 2/2 Export + upload to App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo ""
echo "Uploaded. The build will show as 'Processing' in App Store Connect for a"
echo "few minutes, then becomes selectable on the app's version page."
