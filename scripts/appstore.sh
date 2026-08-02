#!/bin/bash
#
# Archive, sign (Apple Distribution), and upload TopNotch to App Store Connect.
#
# This is a DIFFERENT path from release.sh (which does Developer ID + notarize
# for distribution OUTSIDE the store). Use this one only for Mac App Store.
#
# Usage:
#   ./scripts/appstore.sh              # archive, sign, and UPLOAD
#   ./scripts/appstore.sh --dry-run    # archive + sign to a local .pkg, NO upload
#   BUILD_NUMBER=42 ./scripts/appstore.sh   # force a specific build number
#
# The build number defaults to a UTC timestamp (YYYYMMDDHHMM), which is unique
# and monotonically increasing — App Store Connect rejects duplicate/lower ones.
#
# Prerequisites (see scripts/README-release.md):
#   1. For a real upload: an app record for com.yashsharma.TopNotch exists in
#      App Store Connect. (Not needed for --dry-run.)
#   2. scripts/asc-credentials.local.sh exists (git-ignored) and exports:
#        ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH   (App Store Connect API key)
#      The key MUST have the App Manager (or Admin) role. The Developer role
#      cannot create the distribution cert/profile (cloud signing permission
#      error), so the notarization key is not sufficient for this script.
#   3. You're signed into the Apple ID (team 8B8KZZ8HVU) in Xcode so automatic
#      signing can create the Apple Distribution cert + App Store profile.
#
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

PROJECT="TopNotch.xcodeproj"
SCHEME="TopNotch"
CONFIG="Release"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/TopNotch-appstore.xcarchive"
EXPORT_DIR="$BUILD_DIR/appstore-export"
BASE_PLIST="scripts/ExportOptions-AppStore.plist"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"

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

AUTH=( -allowProvisioningUpdates
       -authenticationKeyPath "$ASC_KEY_PATH"
       -authenticationKeyID "$ASC_KEY_ID"
       -authenticationKeyIssuerID "$ASC_ISSUER_ID" )

echo "==> Build number: $BUILD_NUMBER  (dry-run: $DRY_RUN)"

echo "==> 1/2 Clean + archive ($CONFIG)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${AUTH[@]}" \
  clean archive

# For a dry run, export a signed package locally (destination=export) instead of
# uploading. This still exercises Apple Distribution signing + provisioning.
PLIST="$BASE_PLIST"
if [[ "$DRY_RUN" == "1" ]]; then
  PLIST="$BUILD_DIR/ExportOptions-AppStore-dryrun.plist"
  cp "$BASE_PLIST" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :destination export" "$PLIST"
fi

echo "==> 2/2 Export$([[ "$DRY_RUN" == "1" ]] && echo " (local, no upload)" || echo " + upload to App Store Connect")"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$PLIST" \
  -exportPath "$EXPORT_DIR" \
  "${AUTH[@]}"

echo ""
if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry run OK. Signed package(s) in: $EXPORT_DIR"
  echo "Signing + provisioning are valid. Re-run without --dry-run to upload."
else
  echo "Uploaded (build $BUILD_NUMBER). It will show as 'Processing' in App Store"
  echo "Connect for a few minutes, then becomes selectable on the version page."
fi
