# Building an unsigned IPA on GitHub Actions

This project cannot produce an installable IPA on the Linux development host: compiling
SwiftUI requires an Apple SDK. GitHub-hosted **macOS** runners have Xcode, so they can build
the app and package it as an IPA.

The result is **unsigned**. iOS refuses unsigned apps; you must sign the IPA with your own
certificate and provisioning profile before installing it. AppHub does not ship, request, or
share certificates, and does not bypass Apple revocation checks.

## What the workflow does

Workflow: `.github/workflows/build-ipa.yml`

1. **`core-tests`** (Ubuntu): installs Swift 6.0.3 and runs `swift test` in `Core/` (90 tests).
2. **`build-ipa`** (macOS):
   - installs XcodeGen;
   - validates the localization catalog (`tools/generate_localization.py --check`);
   - generates `App/DreamByteAppHub.xcodeproj`;
   - runs `xcodebuild` for `generic/platform=iOS` with code signing disabled;
   - packages `Payload/DreamByteAppHub.app` into `DreamByteAppHub-unsigned.ipa`;
   - uploads the IPA as a workflow artifact, plus the `xcodebuild` log if the build fails.

The workflow triggers on manual dispatch, pushes to `main`, tags, and pull requests.

## Steps

1. Put this folder in a GitHub repository. Public repositories get free macOS runner
   minutes; private repositories consume minutes at GitHub's macOS multiplier.
2. Open **Actions → Build unsigned IPA → Run workflow**.
3. Wait for both jobs. Download the `DreamByteAppHub-unsigned-ipa` artifact.
4. Sign the IPA on your iPad with your own certificate and a signing tool that accepts
   imported `.p12` + `.mobileprovision` files, then install it.

The current successful build is published as a GitHub Release asset:

<https://github.com/jesusxal777-boop/DreamByte-AppHub/releases/tag/unsigned-0.1.0>

That page downloads the IPA directly on the iPad (public repository, no login needed). It is
still unsigned.

## Signing on the iPad: what is real

- **You need a valid signing identity.** An Apple Developer Program certificate
  (development or ad-hoc) must include your iPad's UDID in its provisioning profile.
  Enterprise certificates work only within their program's rules.
- **The bundle ID must match your profile.** The project builds
  `com.dreambyte.apphub` by default. If your certificate/profile uses another App ID,
  set the `bundle_identifier` workflow input (or change
  `PRODUCT_BUNDLE_IDENTIFIER` in `App/project.yml`) and rebuild.
- **Free Apple IDs are limited and awkward.** On-device signers generally need an imported
  certificate; a free personal team usually requires a computer-based tool
  (AltStore/SideStore/Xcode) at least once.
- **AppHub cannot sign for you.** The `Local signing` mode stays `notImplemented` until a
  real Mach-O + CMS signer exists. Use an external signer for this workflow.
- **AppHub cannot confirm the install.** After signing, iOS performs the installation; the
  app has no way to observe it.

If you use an OTA flow, host the **signed** IPA and its `manifest.plist` over HTTPS and open
the `itms-services://` link in Safari. That is what the app's OTA screen generates.

## Honest limitations

- The SwiftUI layer was authored on Linux and is now type-checked by CI. The first run
  failed with four Swift errors and an XcodeGen `info:` block that overwrote the custom
  `Info.plist`; all five were fixed, and the next run passed. Future changes are still
  compiled only when the workflow runs.
- The workflow uses `macos-15` (Xcode 16.4, iOS 18.5 SDK). The Liquid Glass code path is
  guarded by `#if compiler(>=6.2)` / `if #available(iOS 26.0, *)`, so it compiles the
  fallback here. To exercise it, switch `runs-on` to a macOS 26 runner with Xcode 26+.
- The unsigned IPA has no `embedded.mobileprovision` and no valid signature. It is a build
  artifact, not an installable app.
- Do not commit certificates, provisioning profiles, passwords, or pairing files. The
  workflow uses no secrets by design.

## Local macOS equivalent

If you have a Mac with Xcode:

```bash
brew install xcodegen
cd App
xcodegen generate
xcodebuild \
  -project DreamByteAppHub.xcodeproj \
  -scheme DreamByteAppHub \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
cd ..
CONFIGURATION=Release bash tools/package_unsigned_ipa.sh
```
