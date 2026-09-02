# Releasing TopNotch (Developer ID + Notarization)

TopNotch is distributed **outside the App Store**, signed with a **Developer ID
Application** certificate and **notarized** by Apple so Gatekeeper lets it run on
any Mac.

Team ID: `8B8KZZ8HVU` · Bundle ID: `com.yashsharma.TopNotch`

## One-time setup

You only do this once. It requires your Apple account (paid Developer Program).

### 0. Install create-dmg
```sh
brew install create-dmg
```
Used to build the install window (app icon + Applications drop target).

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
verify with `spctl`/`stapler` → build `build/TopNotch.dmg` (app icon on the left,
Applications drop target on the right) → notarize and staple the dmg itself →
also emit `build/TopNotch.zip`.

Ship the **dmg**; the zip is kept only so older download links keep working.
Upload both to the release:
```sh
gh release upload v1.0 build/TopNotch.dmg
```
The website links to `releases/latest/download/TopNotch.dmg`, so **the asset
filename must stay exactly `TopNotch.dmg`** on every future release or the
Download button 404s.

`build/` is git-ignored, so nothing generated here gets committed.

## Notes
- If notarization is rejected, get the details with:
  ```sh
  xcrun notarytool log <submission-id> --keychain-profile TopNotchNotary
  ```
- A stapled app passes Gatekeeper offline; users won't see the "unidentified
  developer" prompt.
- The dmg is built around the already-stapled app and then notarized and
  stapled itself — that second staple is what keeps the very first open clean
  for a user who is offline.

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

### First submission: use Xcode's GUI (recommended)
`xcodebuild`'s command-line automatic signing still queries **cloud-managed
distribution certificates**, which Apple forbids over an API-key session
(`FORBIDDEN_ERROR`) even when local Apple Distribution + installer certs exist.
Xcode.app's interactive session does *not* have this restriction, so for the
first distribution use the GUI — it registers the App ID, creates the Mac App
Store provisioning profile, signs, and uploads:

1. Create the app record first (App Store Connect → My Apps → + → New App →
   macOS → bundle id `com.yashsharma.TopNotch`).
2. In Xcode: **Product → Archive** (or reuse `./scripts/appstore.sh --dry-run`'s
   archive, which validates the build).
3. Organizer → select the archive → **Distribute App → App Store Connect →
   Upload** → accept the automatic signing prompts.

After the first successful distribution the profile exists, so `xcodebuild`
manual signing works for later uploads.

### Later uploads: CLI
```sh
./scripts/appstore.sh          # uses build/ timestamp as the build number
```
`appstore.sh` auto-assigns a unique build number (a UTC timestamp), so no need
to bump `CURRENT_PROJECT_VERSION` by hand. `--dry-run` archives + signs locally
without uploading.

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
- The app shows a Dock icon by default (right-click → Quit is how people expect
  to close a Mac app). `LSUIElement` is deliberately absent from Info.plist so
  there is no icon flicker at launch; Settings → General → "Show in Dock" flips
  the activation policy at runtime for users who want it hidden. The App Store
  reads the 1024px icon from the asset catalog (a proper macOS icon set).
