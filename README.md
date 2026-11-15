# DreamByte AppHub

A native iOS/iPadOS app for inspecting IPAs, browsing AltSource repositories, managing
downloads, reviewing signing material, and handing off JIT activation to StikDebug —
built by DreamByte Studios.

The UI is SwiftUI with Liquid Glass on iOS 26+ and a material fallback on iOS 18.
All user-facing text is localized at runtime in **Spanish, English, French, and Portuguese**.
Branding is data, not code: the current wordmark, colors, and icon are **placeholders**
meant to be replaced by the official DreamByte Studios assets.

> **Honesty first.** iOS does not let one app install another app, enumerate every
> installed app, import a `.p12` outside the keychain, or enable JIT by itself. AppHub
> does not fake any of those. See [What works](#what-works) and
> [`FEASIBILITY.md`](FEASIBILITY.md).

## Repository layout

```
DreamByteAppHub/
├── Core/                  SwiftPM package, Foundation-only, tests run on Linux
│   ├── Sources/AppHubCore  IPA/ZIP/Mach-O, repositories, downloads, signing,
│   │                       diagnostics, localization, branding
│   ├── Sources/CZlib       ~30-line C shim over system zlib
│   └── Tests/              XCTest suite + generated binary fixtures
├── App/                   SwiftPM package for the iOS app (SwiftUI)
│   └── Sources/DreamByteAppHub
│       ├── Features/       one file per screen
│       └── Resources/Assets.xcassets   placeholder icon + brand mark
├── tools/                 localization generator, fixture generator
├── docs/                  branding guide, build verification log
├── RESEARCH.md            background research and sources
├── FEASIBILITY.md         capability matrix: feasible / limited / impossible
├── ARCHITECTURE.md        module boundaries, data flow, security model
├── ROADMAP.md             phase status
├── TECH_STACK.md          dependencies and build strategy
└── docs/VERIFICATION.md   what was actually compiled and run
```

## What works

| Area | Status |
|---|---|
| IPA inspection (ZIP64, CRC, traversal/bomb limits, XML + binary `Info.plist`, Mach-O slices, FairPlay flag, signature/profile presence, icon extraction) | **Implemented and unit-tested on Linux** |
| AltSource v2 repositories (conditional GET, validation, duplicate detection, persistence, stale-data handling) | **Implemented and unit-tested on Linux** |
| Downloads (progress, cancel, size/SHA-256/bundle-ID validation, quarantine) | **Implemented; end-to-end test downloads from a real local HTTP server on Linux** |
| Provisioning profiles + X.509 summaries (dates, team, devices, entitlements, fingerprints) | **Implemented and unit-tested on Linux** |
| Runtime localization (es/en/fr/pt), parity-tested | **Implemented and unit-tested on Linux** |
| Diagnostics report with path redaction | **Implemented and unit-tested on Linux** |
| SwiftUI screens, Liquid Glass, iPad split view | **Written; Core linkage and resources verified on Linux, UI not compiled** (needs Xcode 26+/SwiftUI) |
| `.p12` import into the keychain | **Implemented with Security.framework; untested without a device** |
| JIT handoff to StikDebug | **Implemented as a URL handoff; cannot verify JIT activation** |
| Installing IPAs | **OTA handoff implemented** — AppHub generates `manifest.plist` / opens `itms-services://`; iOS installs. Direct in-app install is not possible and signing/hosting stay with you |
| Installation modes | **Selectable per package and in Settings** — OTA, local signing, device bridge, external tool. Each shows its real availability; local signing and the bridge stay disabled until implemented and correctly configured |
| Enumerating all installed apps | **Not possible with public APIs** — Library shows AppHub-managed records only |

### Tested vs. untested

- **Tested on this Linux host (Swift 6.0.3, Ubuntu 24.04):** `cd Core && swift build && swift test`
  → **90 tests, 0 failures**. Covers ZIP64/CRC/traversal, IPA inspection, Mach-O and
  `Info.plist` parsing, AltSource decoding/validation/persistence, conditional GET against a
  real local HTTP server, the full download path, provisioning-profile and X.509 parsing,
  localization parity across 4 catalogs, diagnostics redaction, branding overrides, JIT
  handoff models, OTA manifest generation/validation, and the installation-mode
  availability planner.
- **Partially verified on Linux:** `cd App && swift package dump-package` succeeds,
  `swift build` compiles the entire `AppHubCore` dependency and copies the app resources,
  and all 22 SwiftUI source files pass `swiftc -frontend -parse` (syntax only). Type
  checking stops at `no such module 'SwiftUI'`, which is expected on Linux.
- **Compiled on GitHub Actions (macOS 15, Xcode 16.4 / iOS 18.5 SDK):** run
  [#43700153714](https://github.com/jesusxal777-boop/DreamByte-AppHub/actions/runs/43700153714)
  passed both jobs and produced a 1.3 MB `DreamByteAppHub-unsigned.ipa` (arm64, iOS 18.0
  minimum, `com.dreambyte.apphub`). The first run exposed four Swift errors and an
  XcodeGen issue that overwrote the custom `Info.plist`; all five were fixed before this
  successful build.
- **Not run on a device yet:** the keychain/p12 importer, the StikDebug URL handoff, OTA
  installation prompts, and anything that needs an iPhone/iPad. These compile, but only a
  real device can confirm them.

## Build

### Core (Linux or macOS)

```bash
cd Core
swift build
swift test
```

Swift 6.0+ is enough for the core package; verified with Swift 6.0.3 on Linux
(90 tests, 0 failures). No third-party runtime dependencies.

Regenerate the typed localization enum after editing the JSON catalogs:

```bash
python3 tools/generate_localization.py          # validate parity + rewrite L10nKey.swift
python3 tools/generate_localization.py --check  # fail (exit 1) if the enum is stale
```

Rebuild the binary test fixtures (requires Python 3):

```bash
python3 tools/make_test_fixtures.py
```

### App (macOS + Xcode, or Linux + xtool)

The app target requires an iOS 18+ deployment target and an **iOS 26 SDK** to compile the
Liquid Glass path. Xcode 26+ is recommended; older toolchains fall back to materials
automatically (guarded by `#if compiler(>=6.2)`).

**Xcode (recommended).** Either open `App/Package.swift` as a package and add an app
target, or generate a project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd App
xcodegen generate
open DreamByteAppHub.xcodeproj
```

Set your signing team in the target settings, then run on an iPhone/iPad running iOS 18+.

**xtool (Linux, advanced).** Requires Swift 6.4 and a lawfully obtained Xcode 27.1
installation, which this development host did not have. See
[`TECH_STACK.md`](TECH_STACK.md).

### Unsigned IPA via GitHub Actions (no Mac required)

The repository includes `.github/workflows/build-ipa.yml`. On GitHub it builds the app on a
macOS runner, packages an **unsigned** `DreamByteAppHub-unsigned.ipa`, and uploads it as an
artifact. An unsigned IPA is not installable: sign it on your iPad with your own certificate
and provisioning profile. AppHub provides no certificates and does not bypass revocation.

See [`docs/GITHUB_BUILD.md`](docs/GITHUB_BUILD.md) for the full steps, signing constraints,
and honest limitations (the SwiftUI code has not been compiled yet; the first CI run is the
first real type-check).

## Localization

- Catalogs live in `Core/Sources/AppHubCore/Resources/Localization/{es,en,fr,pt}.json`.
- `L10nKey` is generated; never hand-edit it.
- Views call `model.t(.someKey)`; no display string is hardcoded.
- First launch follows the device language (`es-MX` → `es`), with Spanish as the final
  fallback. Settings offers a runtime override and a “system language” reset.
- Adding a language: add `<code>.json`, add the case to `AppLanguage`, rerun the generator,
  and add a test in `LocalizationTests`.

## Branding

The current logo, app icon, and palette are deliberately generic placeholders.
`BrandTheme.placeholder` is marked `isPlaceholder: true` and the UI shows a “temporary
branding” chip. See [`docs/BRANDING_TODO.md`](docs/BRANDING_TODO.md) for the replacement
checklist.

## Security notes

- IPA contents are never executed. ZIP extraction is limited to metadata and an icon
  preview; paths are validated against traversal.
- Downloads are size/SHA-256/bundle-ID checked when the source provides values, and
  stored quarantined.
- `.p12` passwords are used transiently and never stored or logged. Private keys stay in
  the iOS keychain.
- Diagnostics redact filesystem paths and never include pairing files or keys.
- Repository and download URLs must be `http(s)`; `file://`, credentials in URLs, and
  oversized responses are rejected.
- OTA manifests and IPA URLs must be **HTTPS**. AppHub never ships certificates, never
  shares signing identities, and never installs anti-revoke DNS/OCSP bypass profiles.

## License

No license has been chosen yet. Treat the code as **all rights reserved** until DreamByte
Studios publishes a license.
