# Build verification log

This file records what was actually compiled and run, on what host, and what remains
unverified. It exists so the project never claims more than it can demonstrate.

## Host

| Item | Value |
|---|---|
| OS | Ubuntu 24.04.5 LTS (x86_64) |
| Swift toolchain | `swift-6.0.3-RELEASE-ubuntu24.04`, installed locally (no root) at `/home/ubuntu/.local/share/swift-6.0.3/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin` |
| Apple SDK / Xcode | none |
| iOS device | none |
| xtool | 1.24 requires Swift 6.4 + a lawful Xcode 27.1.xip; not available on this host |

## Core package — verified

```bash
cd Core
swift build     # Build complete
swift test      # Executed 96 tests, with 0 failures
```

The suite uses the binary fixtures in `Core/Tests/AppHubCoreTests/Fixtures` (regenerate
with `python3 tools/make_test_fixtures.py`) and starts a real POSIX HTTP server for the
end-to-end download test (`LocalHTTPServer.swift`).

Coverage by suite:

| Suite | What it proves |
|---|---|
| `HashingTests` | SHA-256 and CRC-32 against known vectors |
| `ZipArchiveTests` | ZIP64 central directory, stored/deflated entries, CRC mismatch, path traversal, size limits |
| `IPAInspectorTests` | XML and binary `Info.plist`, Mach-O slices, FairPlay flag, signature/profile presence, unsigned archive |
| `SourceModelsTests` | AltSource v2 decode/encode, legacy flat fields, URL safety, validation |
| `RepositoryServiceTests` | Fetch, conditional GET (304), persistence, replace/remove, duplicate detection |
| `DownloadTests` | Validator (size, SHA-256, bundle ID), stale-job recovery, live HTTP download + validation |
| `SigningTests` | Provisioning-profile CMS extraction, X.509 CN/validity/serial, Codable round trip, store import/remove |
| `LocalizationTests` | 407 keys in parity across es/en/fr/pt, typed enum generated, runtime lookup |
| `AppPackageStoreTests` | Import, replace, rename, delete, persistence, quarantine flags |
| `IPAImportPreflightTests` | Accepts `.ipa`/`.IPA`, rejects other extensions, missing files, directories, and zero-byte files |
| `BrandingDiagnosticsJITTEsts` | Brand override loading/fallback, diagnostics redaction, JIT requirement models |
| `OTAInstallTests` | Apple manifest shape, HTTPS enforcement, bundle-ID/version validation, `itms-services` link round trip |
| `InstallModeTests` | Mode availability rules: OTA, identity-gated signing, pairing/Developer Mode bridge, Apple-only gating, ordered recommendations |

## App package — compiled on macOS CI

Linux can only parse the SwiftUI sources, so the real type-check happens on the GitHub
Actions macOS runner. Run
[#43700153714](https://github.com/jesusxal777-boop/DreamByte-AppHub/actions/runs/43700153714)
(commit `e1545f2`) passed:

```text
Core tests (Linux)               ✓  96 tests, 0 failures
Build unsigned IPA (macOS)       ✓  Xcode 16.4, iOS 18.5 SDK, arm64
```

The artifact is `DreamByteAppHub-unsigned.ipa` (1.3 MB), built with
`CODE_SIGNING_ALLOWED=NO`. Its `Info.plist` reports
`CFBundleIdentifier=com.dreambyte.apphub`, `MinimumOSVersion=18.0`,
`CFBundleLocalizations=[es,en,fr,pt]`, `UIFileSharingEnabled=true`, and
`LSApplicationQueriesSchemes=[stikdebug]`.

The first run found four Swift errors (`BrandTheme` missing import, an unhandled throw in
`rescan`, a wrong `L10nKey` case, and `Bundle.module` in the Xcode target) plus an
XcodeGen `info:` block that silently replaced the custom `Info.plist`. All five were fixed;
the next run passed.

This proves the SwiftUI code type-checks and links for iOS. It does **not** prove runtime
behavior, visual layout, keychain access, or device installation.

## Not verified anywhere yet

- Visual layout on iPhone and iPad, Dynamic Type with fr/pt strings, dark mode, Liquid Glass
  rendering (`if #available(iOS 26.0, *)` path).
- The OTA sheet's actual handoff to SpringBoard: manifest generation and link construction are
  tested, but no iOS device was available to confirm that the install prompt appears.
- The installation-mode UI: the availability planner and persistence keys are tested in Core,
  and `InstallModeSheet`/`SettingsView` now type-check in CI, but they have not been run.
- `.p12` keychain import, provisioning-profile installation handoff.
- Installing an IPA directly from the app (public APIs cannot do this; AppHub hands off via OTA
  or exports).
- JIT activation through StikDebug (handoff URL and prerequisite checks are code-reviewed
  only).
- Device enumeration beyond AppHub-managed records.

## Fixes made while bringing the build up

| File | Fix |
|---|---|
| `Diagnostics/PlatformInfo.swift` | `volumeAvailableCapacityForImportantUsage` is Darwin-only; use it behind `#if canImport(Darwin)` and fall back to `attributesOfFileSystem` |
| `Download/FileDownloader.swift` | `waitsForConnectivity` is get-only in corelibs-foundation; guard the assignment with `#if canImport(Darwin)` |
| `Download/DownloadService.swift` | `Task` returning `()?` fixed to return `Void`; `fileURL(for:)` marked `nonisolated` so non-actor callers/tests can use it |
| `Tests/ZipArchiveTests.swift` | Removed an `Int`/`UInt32` mismatch that made the assertion ambiguous |
| `Tests/SigningTests.swift` | Year check now uses UTC (certificate validity is absolute, not local-time); Codable round trip uses a whole-second `importedAt` because the store encodes ISO-8601 without fractional seconds |
| `Tests/BrandingDiagnosticsJITTEsts.swift` | Raw string delimiter widened so a `"#FF0000"` hex color does not terminate it |
| `Tests/LocalizationTests.swift` | Use `LocalizationCatalog.bundledDirectory` instead of the *test* target's `Bundle.module` |
| `Installation/OTAInstall.swift` | New OTA manifest + `itms-services` module (HTTPS-only, bundle-ID/version validation, percent-encoded link) |
| `Installation/InstallMode.swift` | New mode planner; availability is data-driven so signing/bridge report `needs…` or `notImplemented` instead of pretending to work |
| `DesignSystem/BrandColor.swift` | Added the missing `import AppHubCore` for `BrandTheme` |
| `AppModel.swift` | `rescan` no longer rethrows from inside its `AppHubError` catch block; wrong `L10nKey.requiresSetup` corrected to `.jitRequiresSetup` |
| `DesignSystem/Components.swift` | Replaced `Bundle.module` (not generated for the XcodeGen app target) with a helper that uses `.main` in Xcode and `.module` under SwiftPM |
| `App/project.yml` | Removed the XcodeGen `info:` block: it regenerated `App/Info.plist` and silently dropped the custom keys. `INFOPLIST_FILE` now points at the checked-in file unchanged |
| `App/Package.swift` + assets | Moved `Assets.xcassets` under `Sources/DreamByteAppHub/Resources` so the declared resource exists inside the target; `project.yml` updated to match |
