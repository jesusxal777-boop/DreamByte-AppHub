# DreamByte AppHub — Architecture

## 1. Repository layout

```
DreamByteAppHub/
├── Core/                         # SwiftPM package, cross-platform, testable on Linux
│   ├── Package.swift
│   ├── Sources/AppHubCore/
│   │   ├── IPA/                  # ZIP + Mach-O + Info.plist inspection, package store
│   │   ├── Repository/           # AltSource v2 models, validator, fetching, cache
│   │   ├── Download/             # URLSession downloader + validation
│   │   ├── Signing/              # profile/X.509 inspection, signing records
│   │   ├── JIT/                  # handoff URLs, prerequisites, pairing validation
│   │   ├── Diagnostics/          # report builder, redaction
│   │   ├── Localization/         # runtime JSON catalogs + generated L10nKey
│   │   ├── Branding/             # theme model + placeholder values
│   │   └── Support/              # errors, hashing, byte reader, paths
│   ├── Sources/CZlib/            # system zlib shim (raw DEFLATE)
│   └── Tests/AppHubCoreTests/
├── App/                          # SwiftPM package for xtool/Xcode (iOS)
│   ├── Package.swift
│   ├── Info.plist, project.yml   # XcodeGen spec
│   ├── Sources/DreamByteAppHub/
│   │   ├── DreamByteAppHubApp.swift, RootView.swift, AppModel.swift
│   │   ├── DesignSystem/         # Liquid Glass wrappers, components
│   │   ├── Features/             # Dashboard, IPA, Repositories, Downloads,
│   │   │                         # Certificates, JIT, Library, Diagnostics, Settings
│   │   ├── Platform/             # iOS adapters (p12, share sheet, StikDebug, device)
│   │   ├── Support/              # UTType helpers
│   │   └── Resources/Assets.xcassets # placeholder icon/brand mark
├── tools/                        # localization + fixture generators
├── docs/                         # branding + build verification notes
└── README.md
```

Two packages, one product. The split exists because SwiftUI cannot compile against a Linux Foundation-only toolchain; keeping `AppHubCore` free of UIKit/SwiftUI/Security lets every engine be unit-tested here.

## 2. Module dependency graph

```
AppHubApp (SwiftUI, iOS 26)
   │  uses
   ├── AppHubCore ── AppHubCoreModels
   │      ├── IPAEngine      (ZIP, Mach-O, plist)
   │      ├── RepositoryEngine (URLSession, JSON)
   │      ├── DownloadEngine  (URLSession, SHA-256, validator)
   │      ├── SigningEngine   (CMS plist, X.509 DER, expiry)
   │      ├── Installation    (OTA manifest + itms-services link)
   │      ├── Diagnostics
   │      ├── Localization
   │      └── Branding
   └── iOS adapters: KeychainStore, PKCS12Importer, JITHandoff, InstalledAppsProvider
```

`AppHubCore` has **zero third-party runtime dependencies**. It uses Foundation and a 40-line C shim over the system zlib already present on iOS and Linux.

Planned future modules (not claimed as implemented):

- `DeviceBridge` — pairing-file parsing, loopback proxy, installation_proxy client.
- `JTIBridge` — StikJIT helper-extension integration.

## 3. Core models

| Model | Purpose |
|---|---|
| `AppPackage` | Imported IPA record: id, local URL, inspection result, import date, quarantine state |
| `IPAInspection` | Bundle ID/name/version/build, min OS, architectures, executable, icon path, signature flags, encryption, entitlements summary, warnings/errors |
| `RepositorySource` | id, name, URL, identifier, added date, last refresh, ETag, status |
| `RepositoryApp` + `RepositoryVersion` | AltSource app entries and releases |
| `CertificateRecord` | Profile metadata, team, app ID, dates, devices, entitlements, certificate summaries |
| `DownloadTask` | id, URL, progress, state, bytes, error, validation result |
| `DiagnosticReport` | Structured environment + module states, exportable JSON |

All models are `Codable`, `Sendable`, and immutable where practical.

## 4. Data flow

### IPA import
1. `fileImporter` returns a security-scoped URL.
2. `AppPackageStore` copies it into `Application Support/AppHub/IPAs/<uuid>.ipa` with a temporary `.part` suffix, then atomically moves.
3. `IPAInspector.inspect(url:)` opens the ZIP read-only, enforces limits, extracts only `Info.plist`, the executable header, and icon entries, and returns `IPAInspection`.
4. UI lists the result; failures are stored with a precise reason (not a generic "invalid file").

### Repository browse
1. `RepositoryService.add(url:)` normalizes and validates the URL (https/http only, no credentials, no local file).
2. `SourceFetcher` performs a conditional GET (ETag / If-Modified-Since), capped at 8 MB, 20 s timeout.
3. `AltSourceDecoder` validates identifiers, bundle IDs, versions, and download URLs. Unknown fields are ignored; malformed apps are skipped with per-app warnings.
4. Cached JSON is stored per source; the UI shows stale data plus a refresh error rather than blanking the screen.

### Download
1. `DownloadService.start(app:version:sourceName:)` creates a job and starts a `URLSessionDownloadTask`.
2. Progress is published on the main actor; cancellation removes partial files. Interrupted jobs are marked failed on relaunch (no resume yet).
3. On completion, `DownloadValidator` checks size, optional SHA-256, bundle ID, ZIP integrity, and encryption flag.
4. The file is stored quarantined. **Nothing is executed or installed automatically.**

### OTA install handoff
1. The user either pastes an `itms-services://` link / HTTPS manifest URL, or asks AppHub to generate `manifest.plist` from an inspected IPA and the public HTTPS IPA URL.
2. `OTAInstallManifest` validates bundle ID, version, title, and HTTPS-only URLs, then emits Apple's `items → assets/metadata` plist.
3. `OTAInstall.itmsServicesURL(manifestURL:)` percent-encodes the manifest and produces the `itms-services://?action=download-manifest&url=…` link.
4. The UI opens it through `openURL`; **iOS** downloads and installs. AppHub cannot observe success, and does not sign, host, or bypass revocation.

### Installation mode selection
1. `InstallModePlanner` takes an `InstallCapabilities` snapshot (Apple platform, signing identity, pairing file, Developer Mode, pipeline readiness) and returns an availability for each mode.
2. Availability is one of `available`, `needsSigningIdentity`, `needsPairingFile`, `needsDeveloperMode`, `requiresApplePlatform`, or `notImplemented(reason)` — never a bare boolean.
3. The app builds that snapshot from its real state (`signingRecords`, `capabilities`, OS version). The IPA detail sheet and Settings render the same planner output, so the UI cannot claim a mode works when it does not.
4. The preferred mode persists in `UserDefaults` and only preselects an action; it does not bypass availability checks.

## 5. Security boundaries

| Risk | Mitigation |
|---|---|
| ZIP path traversal | Reject absolute paths, `..`, backslashes, and entries outside `Payload/`; never extract to disk except selected metadata |
| ZIP bombs | Max entries (100k), max central-directory size (64 MB), max uncompressed metadata (16 MB), compression-ratio guard |
| Malicious plist | `PropertyListSerialization` only with bounded data; validate key types |
| SSRF / local network | Repo and download URLs restricted to http(s); no `file://`; size/time caps |
| Untrusted downloads | Quarantine flag, structural validation, explicit user action before sharing/installing |
| Credentials | Never stored in source; p12 passwords used transiently and not logged; private keys remain in Keychain |
| Pairing files | Treated as secrets, excluded from diagnostics exports and backups where possible |

## 6. Persistence

- **IPAs:** `Application Support/AppHub/IPAs/`
- **Repo cache:** `Caches/AppHub/Repositories/*.json`
- **Downloads:** `Application Support/AppHub/Downloads/`
- **Settings:** `UserDefaults` (language override, JIT method, preferred installation mode, theme overrides)
- **Keychain:** p12 identity references only (iOS)
- **Exports:** temporary directory, removed after sharing

A single `AppHubPaths` value resolves these locations and is injectable for tests.

## 7. Localization architecture

- Four JSON catalogs (`es`, `en`, `fr`, `pt`) under `Core/Sources/AppHubCore/Resources/Localization/`.
- `LocalizationCatalog` loads every catalog **at runtime**, so switching language does not
  relaunch the app and does not depend on `Bundle.main` language hacks. The same loader is
  exercised on Linux.
- Language resolution: explicit user override → device preferred language match
  (`es-MX` → `es`) → Spanish (primary development language) fallback.
- UI never contains literal display text. `L10nKey` is a generated, typed enum; a test
  asserts **key parity across all four languages, no empty values, and no key drift**.
- Layouts use flexible widths, `fixedSize(horizontal: false, vertical: true)`,
  `lineLimit` + `minimumScaleFactor` so French/Portuguese strings do not clip.
- Adding a language = one JSON file + one `AppLanguage` case + regenerate `L10nKey`;
  no view changes.
- Technical identifiers (bundle IDs, API names, code symbols) are never translated.

## 8. Branding architecture

All identity is data, not code:

```
BrandTheme {
  displayName, wordmarkText,
  primaryHex, secondaryHex, accentHex,
  logoAssetName, appIconAssetName,
  cornerRadius, usesLiquidGlass
}
```

- Default values are **temporary placeholders** (`BrandTheme.placeholder`), marked in code and UI.
- `branding.json` in the app bundle can override every field without touching Swift.
- The logo view draws a simple geometric placeholder via SwiftUI shapes when the asset is absent; replacing `logoAssetName` with the official asset is the only change needed later.
- `Assets.xcassets` contains a generated placeholder app icon labeled TEMP in `docs/BRANDING_TODO.md`.
- No final mascot, wordmark, or logo is invented or treated as permanent.

## 9. UI structure (SwiftUI)

- `RootView` → adaptive `TabView` (iPhone) / `NavigationSplitView` (iPad).
- Sections: Dashboard, IPA Library, Repositories, Downloads, Certificates, JIT, Diagnostics, Settings.
- Design system: `GlassPanel`, `StatusChip`, `SectionHeader`, `EmptyStateView`, `MetricTile`, `PrimaryButton`.
- iOS 26: `.glassEffect`, `GlassEffectContainer`, glass button styles. Fallback: `.ultraThinMaterial` + strokes for iOS 18.
- Navigation state is value-based (`NavigationPath`), screens are small and composable.
- Motion: restrained spring transitions, no decorative blur storms.

## 10. Concurrency

- Core services are `actor`s where they mutate state (`AppPackageStore`, `DownloadService`, `RepositoryService`).
- UI state uses `@MainActor @Observable` stores.
- Inspection and parsing run off the main thread via `Task.detached` or actor isolation.
- All errors cross module boundaries as typed `AppHubError` values with localized descriptions.

## 11. Testing strategy

| Layer | Test |
|---|---|
| ZIP reader | Synthetic IPAs: stored/deflated entries, CRC mismatch, traversal names, ZIP64 |
| Info.plist | XML + binary plist fixtures |
| Mach-O | Thin arm64, fat arm64+arm64e, encrypted flag |
| SHA-256 | NIST vectors |
| AltSource | Valid v2, missing fields, bad URLs, duplicate IDs, unknown fields, v1 fallback |
| Localization | 4-language parity, placeholders, no missing keys |
| Downloads | Validator unit tests (size/hash/structure) |
| Diagnostics | Stable JSON schema |

Device-dependent paths are compiled but untested here and labeled as such.

## 12. Build & release strategy

1. **Now:** core engines + tests on Linux; full SwiftUI source.
2. **Compile:** macOS + Xcode 27.1 (straightforward), or Linux + xtool 1.24 + Swift 6.4 + lawful Xcode 27.1.xip.
3. **Sign:** free Apple ID for development (7-day, 3-app limit) or paid team for ad-hoc/TestFlight-style distribution.
4. **Install:** xtool `devices`/`install`, Xcode, or export IPA to AltStore/SideStore.
5. **App Store:** not a target — app enumeration/installation features are not App Store-safe; distribute as a development/sideload build.

## 13. Key decisions

| Decision | Why |
|---|---|
| Two SwiftPM packages | Keeps Linux-testable core free of Apple-only frameworks |
| No third-party runtime libraries | Supply-chain safety, small binary, no license friction |
| Custom ZIP reader | We need only metadata; avoids a dependency and gives strict limits |
| AltSource v2 native | Immediately compatible with existing repositories |
| Runtime `.strings` loader | True in-app language switching, testable on Linux |
| Data-driven branding | Branding arrives later; replacement must be trivial |
| Honest capability states | The brief forbids fake functionality |
