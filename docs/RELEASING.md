# Releasing Vellum

Choose the next version in the 0.8.x series after the latest published release. For local testing, create an independent app with a fresh name and bundle identifier. For example, when preparing 0.8.9:

```sh
preview_id="$(date +%Y%m%d%H%M%S)"
APP_NAME="Vellum Preview $preview_id" \
APP_BUNDLE_ID="com.abyssskb.vellum.preview.build$preview_id" \
APP_VERSION=0.8.9 \
scripts/package-app.sh
open "dist/Vellum Preview $preview_id.app"
```

Keep the user's current Vellum running while opening the preview.

For end-to-end updater tests, sign local fixtures with a temporary Ed25519 key and embed its public key in the isolated preview.

Publish the release after the user confirms that local testing passed. Production releases use the default app name and bundle identifier. Release titles, notes, and commit subjects are written in English.

Run `swift test --no-parallel` before publishing. The AppKit/PDFKit tests share application focus and the main run loop. Check README, user guides, and GitHub About against the final features; keep AI positioned as an optional experiment.

The release workflow packages a universal macOS app, creates the DMG, and publishes a signed Sparkle appcast at:

`https://github.com/AbyssSkb/Vellum/releases/latest/download/appcast.xml`

Sparkle verifies the update archive before extraction and the appcast using the public key embedded in the app.

Automatic checks and background downloads are enabled by default. Once an update is ready, users can confirm installation and restart immediately, or continue reading and let Sparkle install it when they normally quit the app.

The app's `CFBundleVersion` and `CFBundleShortVersionString` both use the release version.

## Sparkle signing key

`Resources/UpdateSigningPublicKey.txt` contains the public Ed25519 key embedded in every app. The corresponding private key is stored in the macOS Keychain and the GitHub Actions secret `SPARKLE_PRIVATE_KEY`. Keep a secure backup of the private key; subsequent updates use the same key.

Sparkle's tools are available after resolving the Swift package at `.build/artifacts/sparkle/Sparkle/bin/`. When provisioning the production key, use `generate_keys --account Vellum` to create or retrieve it, and `generate_keys --account Vellum -p` to print its public key. Export the private key to a temporary file with `generate_keys --account Vellum -x /secure/path/key.txt`, add it to Actions with `gh secret set SPARKLE_PRIVATE_KEY < /secure/path/key.txt`, then remove the exported file. Normal releases use the Actions secret; local updater tests use their temporary key. Only the public key belongs in the repository.

The workflow requires `SPARKLE_PRIVATE_KEY` and stops if the archive or feed cannot be signed. `scripts/generate-appcast.sh` uses Sparkle's `generate_appcast`, embeds the English release notes, and verifies the generated feed before publishing it. Run it after all DMG signing and notarization steps, since changing the archive invalidates its update signature.

## Developer ID signing and notarization

Configure the following Actions secrets to distribute a Developer ID signed and notarized app:

- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_SIGNING_IDENTITY` (optional when the imported certificate identifies the signer)
- `KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

The package script signs Sparkle's nested services and installer tools before the framework and app. Local builds use an ad-hoc signature. Sparkle's Ed25519 update signing remains required independently of Developer ID signing.
