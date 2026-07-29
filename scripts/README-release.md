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
