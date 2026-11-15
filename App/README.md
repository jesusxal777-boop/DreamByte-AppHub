# DreamByte AppHub — iOS app target

SwiftUI application package. It depends on `../Core` (`AppHubCore`) for every engine and
adds the iOS-only adapters (keychain, share sheet, StikDebug URL scheme).

## Requirements

- iOS 18.0+ deployment target (iOS 26 recommended for Liquid Glass)
- Xcode 26+ (Swift 6.2+) to compile the `glassEffect` path; Xcode 16 compiles the
  material fallback because the glass calls are behind `#if compiler(>=6.2)`
- XcodeGen (optional) if you prefer a generated `.xcodeproj`
- Linux/xtool 1.24 is supported in principle but needs Swift 6.4 + Xcode 27.1

## Generate and run with Xcode

```bash
brew install xcodegen          # once
cd App
xcodegen generate
open DreamByteAppHub.xcodeproj
```

1. Select the `DreamByteAppHub` target → Signing & Capabilities.
2. Choose your team and change `PRODUCT_BUNDLE_IDENTIFIER` if needed.
3. Pick an iPhone or iPad simulator/device and run.

Free Apple IDs work for development but limit you to 3 apps per device and 7-day
provisioning profiles; iOS will refuse to launch the app after the profile expires.

## Run with xtool

`xtool` builds a SwiftPM executable into an app bundle. This host could not provide the
required toolchain (see `../TECH_STACK.md`), so the exact command is documented as
**untested here**:

```bash
cd App
xtool auth login        # Apple ID, done locally; AppHub never sees credentials
xtool dev               # build + install on a connected device
```

Info.plist keys that matter:

| Key | Why |
|---|---|
| `LSApplicationQueriesSchemes = [stikdebug]` | Required for `canOpenURL("stikdebug://")` and the JIT handoff |
| `UTImportedTypeDeclarations` + `CFBundleDocumentTypes` | Declares `com.dreambyte.apphub.ipa` so Files can match/open `.ipa` files |
| `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` | Lets users drop IPAs into the app's Documents folder; they are imported at launch |
| `CFBundleLocalizations = [es,en,fr,pt]` | Declares the supported languages to iOS |
| `UILaunchScreen` | Uses `LaunchBackground` from the asset catalog |

## What is real vs. handed off

- Imported IPAs are copied, inspected, and quarantined locally. They can arrive through the
  document picker, the Files/share sheet (`.onOpenURL`), or the app's Documents folder.
- `.mobileprovision` files are parsed locally (CMS payload, dates, entitlements, devices).
- `.p12` files are imported into the keychain through `SecPKCS12Import`; the password is
  never persisted.
- Downloads are validated (size, SHA-256 when published, bundle ID) and never installed.
- Installation is impossible with public APIs, but **OTA handoff is real**: AppHub generates
  `manifest.plist` or opens `itms-services://` links and iOS performs the install.
- Installation modes are user-selectable (OTA, local signing, device bridge, external tool).
  Local signing and the device bridge report their real prerequisites and stay unavailable
  until the pipeline exists.
- JIT is a StikDebug handoff. The app cannot read another process's PID, so the handoff
  form asks for it explicitly and states that success is not auto-confirmed.

## Compile status

The SwiftUI layer was authored on Linux and is now compiled by
`.github/workflows/build-ipa.yml` on a macOS runner. The first run found four Swift errors
and an XcodeGen `info:` block that replaced the custom `Info.plist`; after fixing them, the
build passed with Xcode 16.4 / iOS 18.5 SDK and produced an arm64 unsigned IPA. Version
0.1.1 adds the declared `.ipa` UTI, document types, picker fallbacks, and the
Documents-folder import path. See `../docs/VERIFICATION.md` for the run link and details.

Still unverified without hardware:

- runtime behavior of `Tab(value:content:label:)`, `NavigationSplitView` selection, and
  Liquid Glass (`glassEffect(_:in:)`) only on iOS 26;
- keychain/p12 access and StikDebug handoff;
- visual layout with long fr/pt strings, Dynamic Type, and iPad split view.

The core package remains the tested part.

## Resources

`Sources/DreamByteAppHub/Resources/Assets.xcassets` is the single asset location. It sits
inside the SwiftPM target so `Package.swift` can process it, and `project.yml` includes
the same folder for XcodeGen. Put a `branding.json` next to it to override the placeholder
brand at runtime (see `../docs/BRANDING_TODO.md`).

## Tests

The app target has no UI tests yet (requires a simulator). Core behavior is covered by
`Core/Tests/AppHubCoreTests`.
