# Mac Pulse updates

Mac Pulse 1.4.0 is the first release with an in-app updater. Users on 1.3.1 or
earlier need to download and replace the app once. Subsequent updates can be
installed through Sparkle without an account or a paid Apple Developer membership.

## User controls

- Check manually from **Mac Pulse → Check for Updates…**, the menu-bar panel,
  or **Settings → Updates**.
- Automatic checks default to once every 24 hours while the app is running.
  Sparkle schedules checks across launches and shows release notes when an
  eligible newer build is available.
- Automatic downloading/installation is off by default and can be enabled in
  Settings. Sparkle can install a prepared update when the app quits.
- Sparkle saves update preferences and the last check time. Updating the app
  preserves the existing monitoring history and Cleanup data directories.

The release app is ad hoc signed, not Developer ID signed or Apple-notarized.
The updater does not remove macOS first-install approval requirements. Install
the app in Applications before updating it; an app on a mounted read-only DMG
cannot replace itself there.

## Feed and verification

The app reads the signed feed at:

<https://raw.githubusercontent.com/thelordzeus/mac-monitor/main/appcast.xml>

The feed points to immutable, versioned ZIP downloads in this repository's
GitHub Releases. Both the feed and ZIP have Ed25519 signatures. The app embeds
the public key and requires valid signatures before extracting an update. The
signed-feed failure timeout is disabled, so a signature failure cannot fall
back to an unsigned feed. HTTPS protects the production feed and download links.

Sparkle 2.10.0 is pinned in `Package.swift` and `Package.resolved`. The build
script embeds its framework and signs the nested installer and updater tools
before signing the host app. The app is not sandboxed and does not use Sparkle's
optional sandbox XPC services.

System profiling is disabled. Update checks do not upload metrics, Cleanup
results or history. GitHub receives normal network requests, including the
client IP address and HTTP headers.

## Publishing a release

1. Increment both `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`. Sparkle compares the monotonically increasing build
   number. Keep the bundle identifier and update public key unchanged.
2. Write `docs/releases/v<version>.md`, update `docs/INSTALL.txt` and any relevant
   README text or screenshots. Complete the appropriate regression checks.
3. Build, package and generate the signed feed:

   ```sh
   ./scripts/build.sh
   ./scripts/package.sh --skip-build
   ./scripts/make-appcast.sh
   python3 -m unittest discover -s Tests/UpdateReleaseTests -v
   ```

4. Commit the source, release notes and generated root `appcast.xml`, then push
   to `main`. Do not edit the XML after signing it.
5. Publish:

   ```sh
   ./scripts/publish-release.sh
   ```

6. Verify the release tag matches the pushed commit, all four release assets
   exist, and the public feed/download links work. Test **Check for Updates…**
   in the packaged app.

The feed generator checks that the Keychain key matches the app's public key,
signs the current ZIP and feed, embeds release notes, and retains existing feed
entries. It does not generate delta archives. The publisher requires a clean
working tree and a pushed `main` commit; it verifies archive/feed signatures,
bundle signatures, the DMG and checksums before creating the release. It uploads
the DMG, ZIP, `SHA256SUMS` and signed `appcast.xml` without overwriting old releases.

The feed is pushed just before the release assets are uploaded. During that
short publishing window the new download can be unavailable; checking again
after publication succeeds. If publication fails, finish uploading the exact
signed files before announcing the release.

## Signing key

The private key is stored in the releasing Mac's Keychain under account
`mac-pulse`. Only the public key is committed. Preserve a secure backup of the
private key before changing the release machine; Sparkle's official
`generate_keys` tool can export/import it. Never commit, paste into an issue,
or log a private key. Replacing the key without a planned key migration breaks
updates for existing installations.

`SPARKLE_KEY_ACCOUNT` can select another Keychain account, but its public key
must match the one already embedded in the app. A source build can check for
official updates; publishing trusted updates requires the existing private key.

## Verification for 1.4.0

- Release build launches with Sparkle embedded, and strict deep code-signature
  verification passes. DMG verification and release checksums pass.
- Existing Cleanup tests: 112 passed; three conditional media tests skipped
  because FFmpeg was unavailable.
- Four release acceptance tests pass: authentic signatures verify with only
  the public key; a modified feed, modified ZIP payload and unsigned feed are
  rejected.
- Sparkle itself accepted a signed local test feed and rejected a deliberately
  modified feed with an invalid-signature error.
- An isolated older test app downloaded a signed update, installed build 9,
  and relaunched. Its installed executable matched the signed test archive;
  Settings displayed version 1.4.0. Test-only identifiers and local routing
  were confined to temporary bundles, outside the production release.
- The Settings page and manual update dialog were checked in the native app.

These checks were run on an Apple M4 Mac with macOS 27. Intel Macs, every
supported macOS version, administrator-owned installs and unattended background
installation across a full daily cycle have not been tested.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[publishing updates](https://sparkle-project.org/documentation/publishing/),
[configuration](https://sparkle-project.org/documentation/customization/).
