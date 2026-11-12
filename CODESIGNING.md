# Release Signing and Updates

AlwaysOn ships without an Apple Developer ID. Releases are signed with a long-lived self-signed certificate, and updates are delivered with [Sparkle](https://sparkle-project.org) and verified with an EdDSA key.

## Why a self-signed certificate

macOS ties Accessibility access to the app's *designated requirement*, a rule recorded in the code signature that says which code counts as "the same app".

- **Ad-hoc signature** (`codesign --sign -`, used by releases up to 1.11): the requirement is the exact hash of that build. Every new build fails it, so macOS treats each update as a different app. That's why you had to remove AlwaysOn from Accessibility settings and add it again after each update.
- **Self-signed certificate**: the requirement becomes the bundle identifier plus the certificate's hash (`identifier "com.alwayson.app" and certificate … = H"…"`). Every build signed with the same certificate meets it, so Accessibility access carries over.

The certificate does not make Gatekeeper trust the app. The first launch still needs **Open Anyway** in Privacy & Security. Updates installed by Sparkle don't, because Sparkle removes the download quarantine flag.

**Never replace the certificate.** A release signed with a new one resets Accessibility access for every user once. Set the `SIGNING_CERT_SHA1` variable and the release workflow refuses to sign with any other certificate.

## How updates work

1. The app reads `https://alwayson.hafiezulzikry.com/appcast.xml` (`SUFeedURL`). The site's Worker counts the check and redirects to `https://github.com/hafiezul/AlwaysOn/releases/latest/download/appcast.xml`, the appcast attached to the latest release. The redirect doesn't depend on PostHog, but it does need the site to be up; see [site/README.md](site/README.md).
2. If the appcast lists a higher build number (`sparkle:version`, the commit count), Sparkle offers the update.
3. Sparkle downloads the DMG, checks its EdDSA signature against `SUPublicEDKey` in the running app, and checks that the new app has the same code signing requirement. Then it replaces the app and relaunches it.

Builds without `SPARKLE_PUBLIC_ED_KEY` (local and CI builds) have no updater; **Settings > Updates** falls back to a manual GitHub release check.

## One-time setup

On your Mac, from the repository:

```bash
Scripts/setup-release-signing.sh            # writes to ~/AlwaysOn-release-signing
```

The script:

1. Creates the self-signed code signing certificate (valid for 20 years) as `cert.p12` with a random password.
2. Creates the Sparkle EdDSA key pair with OpenSSL 3 (`brew install openssl@3`), which needs no keychain and so also works over SSH. Without OpenSSL 3 it falls back to Sparkle's `generate_keys` (version and SHA-256 pinned), which also stores the key in your login keychain under the account `alwayson-release`.
3. Prints the GitHub Actions secrets and variables, and offers to set them with `gh`:

| Name | Kind | Value |
| --- | --- | --- |
| `MACOS_SIGNING_CERT_P12` | secret | `cert.p12.base64` |
| `MACOS_SIGNING_CERT_PASSWORD` | secret | `cert-password.txt` |
| `SPARKLE_ED_PRIVATE_KEY` | secret | `sparkle-private-key.txt` |
| `SPARKLE_PUBLIC_ED_KEY` | variable | the public key it prints |
| `SIGNING_CERT_SHA1` | variable | the certificate SHA-1 it prints |

4. Offers to import the certificate into your login keychain, so your local builds can keep Accessibility access too.

Back up `~/AlwaysOn-release-signing` (a password manager works) and keep it out of git. Running the script again reuses what's there.

Over SSH, macOS doesn't unlock the login keychain, so `gh` on the Mac may look logged out and the keychain import fails. Answer no to both, then copy the files to the GitHub settings with `gh` from another machine.

## Cutting a release

From the Actions tab, run **Release** with a version like `1.12.0`, or push a `v1.12.0` tag. Tick **dry run** to build, sign, and package without publishing; the DMG and appcast are uploaded as a workflow artifact. A dry run is a good first check that the secrets work.

The workflow:

1. Validates the version and, for Actions-tab runs, that the tag doesn't exist yet. The tag is created only when the release is published, so a failed run can be rerun.
2. Fails early if a secret or variable is missing.
3. Imports the certificate into a temporary keychain, checking it against `SIGNING_CERT_SHA1` when that variable is set.
4. Builds a universal Release app with `Scripts/build-app.sh` and signs it from the inside out: the CLI helper, Sparkle's helpers, Sparkle, then the app. It fails if the designated requirement isn't certificate-based.
5. Packages the drag-install DMG with `Scripts/build-dmg.sh`. The installer window's art and geometry live in `Scripts/dmg/`: edit `layout.json` or `make-background.py`, then rerun `python3 Scripts/dmg/make-background.py --preview <file.png>` and commit the regenerated PNGs.
6. Signs the DMG with the Sparkle EdDSA key and checks that the app carries the matching public key.
7. Builds the release notes from GitHub's generated notes (merged PRs since the last tag) plus install instructions. If no PRs were merged, for example when work was pushed straight to `main`, it lists the commit subjects since the last tag instead. It writes `appcast.xml` with the same notes as HTML.
8. Publishes the release with the DMG and `appcast.xml`, and deletes the temporary keychain.

Steps that reach the network (fetching Swift packages, generating the notes, publishing) retry on failure, and Swift packages are cached between runs. If a run fails after the release was created, rerun it: when the release already exists, the workflow only re-uploads the DMG and `appcast.xml`.

## Local builds

```bash
Scripts/build-app.sh                                    # ad-hoc, no updater
SIGN_IDENTITY=<certificate SHA-1> Scripts/build-app.sh  # same requirement as releases
```

Add `SPARKLE_PUBLIC_ED_KEY=<public key>` to build an app that updates itself.

Hardened runtime stays off: its library validation needs an Apple Team ID, which a self-signed certificate doesn't have.

## Why not a Developer ID

Skipping the **Open Anyway** step on first launch requires an Apple Developer ID certificate and notarization, which need a paid Apple Developer membership (US$99 a year). AlwaysOn is free, so releases use the self-signed certificate instead. That's a deliberate choice, not a gap. The README explains it to users in [Why macOS asks you to confirm the first launch](README.md#why-macos-asks-you-to-confirm-the-first-launch).

If this is ever revisited: Sparkle updates work the same way with either certificate, but switching to a Developer ID resets Accessibility access for every user once, like any certificate change. Update the README section and the site's install note at the same time.
