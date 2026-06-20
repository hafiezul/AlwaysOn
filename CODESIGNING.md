# Unsigned Release Workflow

AlwaysOn releases are built for manual installation without an Apple Developer ID.

The GitHub Actions release workflow:

1. Builds `AlwaysOn.app` in Release configuration.
2. Forces `ALWAYSON_UPDATE_MODE=manual`.
3. Disables Xcode-managed signing during the build.
4. Ad-hoc signs the finished app bundle.
5. Verifies the ad-hoc signature.
6. Packages a single drag-install DMG.
7. Publishes the DMG SHA-256 in the GitHub release notes.

## Signing Command

The release workflow signs the app with a local ad-hoc identity:

```bash
codesign --force --deep --sign - --options runtime build/Build/Products/Release/AlwaysOn.app
codesign --verify --deep --strict --verbose=2 build/Build/Products/Release/AlwaysOn.app
```

This gives macOS a stable signed bundle to evaluate, but it does not make the app trusted as an identified developer download.

## User Install Behavior

Users install the app from Finder:

1. Download the latest DMG from GitHub Releases.
2. Open the DMG.
3. Drag `AlwaysOn.app` to Applications.
4. If Gatekeeper blocks first launch, Control-click or right-click the app in Finder, choose **Open**, then choose **Open** again.
5. Grant Accessibility permission when prompted.

Accessibility permission is still required because AlwaysOn simulates keyboard or mouse input. After replacing the app with a new release, macOS may require users to remove the old AlwaysOn entry from **System Settings > Privacy & Security > Accessibility**, then add and enable `/Applications/AlwaysOn.app` again.

## Fully Trusted Distribution

A fully seamless install for downloaded macOS apps requires an Apple Developer ID certificate and notarization. That path is intentionally not part of the current release workflow.
