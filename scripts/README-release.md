# Releasing TopNotch (Developer ID + Notarization)

TopNotch is distributed **outside the App Store**, signed with a **Developer ID
Application** certificate and **notarized** by Apple so Gatekeeper lets it run on
any Mac.

Team ID: `8B8KZZ8HVU` · Bundle ID: `com.yashsharma.TopNotch`

## One-time setup

You only do this once. It requires your Apple account (paid Developer Program).

### 1. Create a "Developer ID Application" certificate
- Xcode → **Settings → Accounts** → select your Apple ID → **Manage Certificates…**
- Click **+** → **Developer ID Application** → Done.
- Verify it landed in your keychain:
  ```sh
  security find-identity -v -p codesigning | grep "Developer ID Application"
  ```

### 2. Generate an App Store Connect API key (for notarytool)
- <https://appstoreconnect.apple.com> → **Users and Access → Integrations → App Store Connect API**
- **Generate API Key**, role **Developer**.
- Note the **Issuer ID** (top of the page) and the key's **Key ID**.
- **Download the `AuthKey_<KEY_ID>.p8`** — you can only download it once. Keep it
  somewhere safe **outside the repo** (e.g. `~/private/AuthKey_XXXX.p8`).
  Never commit it.

### 3. Store the notary credentials in your keychain (once)
```sh
xcrun notarytool store-credentials "TopNotchNotary" \
  --key ~/private/AuthKey_XXXX.p8 \
  --key-id <KEY_ID> \
  --issuer <ISSUER_ID>
```
This saves them under the profile name `TopNotchNotary` in your login keychain.
The `.p8` itself is not stored in the repo.

## Cutting a release

```sh
./scripts/release.sh
```

It will: clean → archive (Release) → export & Developer-ID sign with hardened
runtime → zip → submit to Apple's notary service (waits) → staple the ticket →
verify with `spctl`/`stapler` → produce `build/TopNotch.zip` to distribute.

`build/` is git-ignored, so nothing generated here gets committed.

## Notes
- If notarization is rejected, get the details with:
  ```sh
  xcrun notarytool log <submission-id> --keychain-profile TopNotchNotary
  ```
- A stapled app passes Gatekeeper offline; users won't see the "unidentified
  developer" prompt.
- To ship a `.dmg` instead of a `.zip`, notarize/staple the `.app` first, then
  build the dmg around the stapled app (or notarize the dmg as well).

---

# Submitting to the Mac App Store

This is a **separate** path from Developer ID above. `scripts/appstore.sh`
archives, signs with **Apple Distribution** + a Mac App Store provisioning
profile (auto-created), and uploads to App Store Connect.

## One-time setup
1. **App record**: create the app for `com.yashsharma.TopNotch` in App Store
   Connect (My Apps → +). Fill listing metadata (see checklist below).
2. **Local credentials** (git-ignored): create `scripts/asc-credentials.local.sh`:
   ```sh
   export ASC_KEY_ID="<KEY_ID>"
   export ASC_ISSUER_ID="<ISSUER_ID>"
   export ASC_KEY_PATH="$HOME/path/to/AuthKey_XXXX.p8"
   ```
   The API key uploads the build and creates provisioning profiles. Use the
   App Manager role.
3. **Create the distribution certificates once, in Xcode** (this is required —
   App Store Connect API keys are FORBIDDEN by Apple from creating cloud-managed
   *distribution* certificates, so the CLI cannot mint them; it fails with
   "You haven't been given access to cloud-managed distribution certificates").
   Xcode → Settings → Accounts → your Apple ID → **Manage Certificates…** → **+**:
   create **Apple Distribution** and **Mac Installer Distribution**. These land
   in your keychain with private keys, and the CLI export then signs with them
   locally (only the provisioning profile is fetched via the API key).
   Verify:
   ```sh
   security find-identity -v | grep -E "Apple Distribution|Mac Installer Distribution"
   ```

## Cutting a build
```sh
./scripts/appstore.sh
```
The build appears as "Processing" in App Store Connect, then becomes selectable
on the version page. Bump `CURRENT_PROJECT_VERSION` (build number) in the project
before each new upload — App Store Connect rejects duplicate build numbers.

## Listing metadata you still need (App Store Connect, in the browser)
- Name, subtitle, description, keywords, promotional text
- **Category** (e.g. Productivity)
- **Screenshots** (macOS sizes, e.g. 2560×1600 / 2880×1800)
- **Support URL** and **Privacy Policy URL** (both required, must be hosted)
- **Age rating** questionnaire
- **App Privacy** answers. Speech runs on-device, and the cloud-upload feature
  was removed, so data collection is minimal — answer honestly per the current
  build.

Notes:
- App Sandbox is already enabled (required for MAS).
- `ITSAppUsesNonExemptEncryption=false` is in Info.plist (only exempt HTTPS/TLS
  is used), so no per-upload export-compliance prompt.
- The app is an accessory (`LSUIElement`) with no Dock icon; the App Store still
  reads the 1024px icon from the asset catalog (now a proper macOS icon set).
