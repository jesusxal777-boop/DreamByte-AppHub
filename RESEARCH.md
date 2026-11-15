# DreamByte AppHub — Technical Research

**Date:** 2026-11-15
**Scope:** iOS/iPadOS 26 application management ecosystem on a Linux development host.
**Rule applied:** every capability below is classified, not assumed. No fabricated APIs.

---

## 1. Development environment audit

| Item | Result |
|---|---|
| OS | Ubuntu 24.04.5 LTS, kernel 6.18.38, x86_64 |
| CPU / RAM | 6 vCPU / 23 GiB |
| Disk | 48 GB total, **4.6 GB free** |
| Swift | **Not installed** (Swift 6.4.2 Linux toolchain downloaded for core testing) |
| Xcode / macOS | **Not available** |
| xtool | 1.24.0 AppImage present (`~/Downloads/xtool-x86_64.AppImage`) |
| usbmuxd / libimobiledevice | Not installed (apt candidates available: usbmuxd 1.1.1, libimobiledevice-utils 1.3.0) |
| Other toolchains | GCC, Python 3, Node 22, Java |
| Network | Available (GitHub, swift.org, Apple docs) |

### Consequence

xtool 1.24's own installation guide requires:

- Swift **6.4** toolchain, and
- **Xcode 27.1.xip** to generate the Darwin Swift SDK (`xtool sdk build` / `setup`).

Xcode 27.1 is a multi-gigabyte download behind an Apple ID login and license acceptance. With 4.6 GB free and no Apple credentials, generating the iOS SDK — and therefore compiling SwiftUI for iOS — is **not possible in this environment**. The 1.12 GB Swift 6.4 Linux toolchain is still installed because it compiles and tests every Foundation-only engine for real.

**Therefore the project separates:**

1. **Core engines** — pure Swift + Foundation (+ zlib C shim): compilable and testable on Linux.
2. **App UI** — SwiftUI/iOS source, complete and organized, but **not compiled here**. Final build requires macOS + Xcode 27.1, or Linux + xtool with Swift 6.4 and a legally obtained Xcode 27.1.xip.
3. **Device deployment** — requires USB/network access to an iPhone/iPad (usbmuxd) plus an Apple ID for signing. No device is attached here.

This is a tooling limitation, not a reason to fake functionality.

---

## 2. Apple signing architecture

An installable iOS app is a ZIP (`Payload/App.app`) containing:

- Mach-O executable(s) for arm64 / arm64e;
- `Info.plist`;
- `embedded.mobileprovision` (provisioning profile);
- `_CodeSignature/CodeResources`;
- optionally frameworks, extensions, asset catalogs.

The provisioning profile is a CMS (PKCS#7) SignedData blob wrapping a property list with `AppIDName`, `TeamIdentifier`, `ExpirationDate`, `Entitlements`, `DeveloperCertificates` (DER X.509), and `ProvisionedDevices`. The app binary is signed with a certificate whose private key is on the developer machine; the profile authorizes the certificate and the device UDID.

Key properties:

- **Free (personal team) accounts:** max 3 installed sideloaded apps per device, 10 App IDs and 3 devices per 7 days; profiles expire after **7 days** and apps stop launching until re-signed. [Apple Developer help]
- **Paid accounts:** 1-year distribution/development profiles; ad-hoc profiles are bound to registered UDIDs; App Store profiles are not usable for direct sideloading.
- **Enterprise (In-House) profiles** require an Apple Developer Enterprise Program membership and are not publicly distributable.
- Revocation is checked by iOS at launch/refresh depending on trust cache state; an app can detect expiry locally, but reliable online revocation checking needs OCSP/CRL and is not guaranteed offline.

Sources:
- Apple Developer account overview — https://developer.apple.com/help/account/basics/about-your-developer-account
- Apple Platform Security, app signing — https://support.apple.com/guide/security/app-code-signing-process-sec7b8d9c2f3e/web

---

## 3. IPA installation: what is actually possible

| Mechanism | Who can use it | AppHub relevance |
|---|---|---|
| App Store | Apple | Not a sideload path |
| MDM `InstallApplication` | MDM-enrolled supervised devices | Requires MDM infrastructure; not usable by a normal app |
| Apple Configurator / Finder | macOS host | External tool |
| Developer install (`installation_proxy` over usbmuxd) | Host with a trusted pairing record | xtool/AltStore/SideStore use this externally |
| EU alternative marketplaces / Web Distribution | Notarized apps, EU, Apple-approved developer | Not available to a hobby app; requires Apple entitlement |
| On-device install (SideStore model) | Sideloaded app + pairing file + loopback VPN | Technically possible with limitations; heavy integration |

**There is no public iOS API that lets an app install another app.** `UIApplication.open` can only open URL schemes; it cannot install a bundle. Any in-app "Install" button that claims otherwise without a helper is a mockup.

The SideStore/AltStore approach is the only computer-free path: a loopback VPN (`em_proxy`) exposes a local usbmuxd-compatible endpoint, `minimuxer` speaks lockdownd/installation_proxy using a device pairing file, and the app signs the IPA with a user certificate before installing. It requires:

- a pairing file obtained once from a computer;
- Developer Mode on the device;
- a loopback VPN profile;
- a valid signing certificate and matching provisioning profile;
- `get-task-allow` and non-App-Store distribution for the host app.

This is feasible for AppHub **as an optional device bridge module**, not as a first-release feature. It cannot be tested on this Linux host without a device and signing identity.

Sources:
- SideStore — https://sidestore.io/
- minimuxer — https://github.com/SideStore/minimuxer
- Apple MDM InstallApplication — https://developer.apple.com/documentation/devicemanagement/installapplication

---

## 4. JIT on iOS 26

JIT requires the target process to hold the `get-task-allow` entitlement and to be marked `CS_DEBUGGED`. On iOS 17.4+, an on-device debugger can enable JIT using a pairing file; on iOS 26 with TXM/SPTM, debugger attach alone is insufficient — each executable region must be prepared through a breakpoint protocol (`brk #0xf00d`, selector in `x16`).

StikDebug (AGPL-3.0, iOS 17.4+) implements the debugger side and exposes `stikdebug://enable-jit?bundle-id=…&pid=…` plus an optional `script-name`/`script-data` for TXM. Integration guidance confirms:

- check `get-task-allow` in the **host** process via Security SPI;
- JIT success cannot be inferred from a successful URL open;
- a helper extension + StikJIT framework is required for built-in activation (two processes, because self-attach deadlocks);
- LocalDevVPN / loopback networking is required;
- behavior is version-sensitive (iOS 26.4 needed StikDebug fixes).

Conclusion: AppHub can **detect prerequisites, explain status truthfully, and hand off to StikDebug**. Universal silent JIT is not possible through public APIs. Bundling StikJIT is a later opt-in module with AGPL compliance implications.

Source: https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md

---

## 5. Repository formats

AltStore/SideStore use a self-hosted JSON source (AltSource v2):

```json
{
  "name": "Source name",
  "identifier": "com.example.source",
  "sourceURL": "https://example.com/apps.json",
  "apps": [{
    "name": "App",
    "bundleIdentifier": "com.example.app",
    "developerName": "Developer",
    "subtitle": "Short line",
    "localizedDescription": "Long text",
    "iconURL": "https://example.com/icon.png",
    "tintColor": "2E7DFF",
    "versions": [{
      "version": "1.0",
      "date": "2026-01-01",
      "downloadURL": "https://example.com/app.ipa",
      "size": 123456,
      "minOSVersion": "16.0",
      "maxOSVersion": "26.9"
    }],
    "screenshotURLs": [],
    "beta": false
  }],
  "news": []
}
```

`identifier` must remain stable; `versions` must be newest-first; `bundleIdentifier` must match the IPA. AppHub implements this format natively and adds an optional namespaced `apphub` extension object for richer metadata without breaking AltStore clients.

Source: https://github.com/altstoreio/AltStore-Docs/blob/master/sources.md

---

## 6. iOS 26 Liquid Glass

SwiftUI in iOS 26 provides native Liquid Glass:

- `.glassEffect(_:in:)` — applies a `Glass` variant in a shape;
- `GlassEffectContainer` — merges nearby glass shapes;
- `.buttonStyle(.glass)` / `.glassProminent`;
- `.backgroundExtensionEffect()`, toolbar and tab bar glass behavior.

Adoption requires building against the iOS 26 SDK. On iOS 18 the same views must fall back to `.ultraThinMaterial`; AppHub uses a single `GlassPanel` wrapper with availability branching so the UI remains buildable for both deployment targets.

Sources:
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- https://developer.apple.com/videos/play/wwdc2025/323/

---

## 7. Certificate and profile inspection

- **Provisioning profile:** CMS SignedData. On Apple platforms `CMSDecoder` (Security.framework) decodes it and yields the embedded plist. Cross-platform fallback: scan the CMS bytes for an embedded XML/binary plist; verify structure and dates but do not claim signature verification.
- **PKCS#12 (.p12/.pfx):** import via `SecPKCS12Import` with a user-supplied password. Private keys never leave the keychain; AppHub stores a keychain reference, not raw key bytes.
- **X.509 fields:** subject/issuer CN, serial, validity, SHA-1/SHA-256 fingerprint. DER parsing is small and can be implemented without dependencies; signature-chain validation requires Apple's trust store.
- **Revocation:** OCSP/CRL is network-dependent and not guaranteed; AppHub reports "not checked" instead of assuming valid.

---

## 8. Linux iOS workflows (summary)

| Tool | What it does | Status here |
|---|---|---|
| xtool | SwiftPM → iOS app, signing, install | CLI works; SDK build blocked by missing Xcode 27.1 |
| Swift 6.4 Linux | Compiles Foundation-only Swift | Installed; used for core tests |
| usbmuxd / libimobiledevice | Device communication | Installable; no device attached |
| Theos | Jailbreak-oriented build system | Not needed; no jailbreak target |
| Docker macOS / cloud Mac | Full Xcode | Excluded (cost / credentials) |

**Recommendation:** treat Linux as the core-logic and UI-authoring environment; treat macOS/Xcode 27.1 (or xtool with a lawful Xcode.xip) as the compile/sign environment. Keep all iOS-only code behind `#if canImport(...)` so the core stays testable here.

---

## 9. Decisions driven by research

1. IPA **inspection** is fully implementable and testable — do it first.
2. IPA **installation** is not a public API — expose a truthful "Prepare / Export / Open in sideload tool" flow now; device bridge later.
3. Certificate import is real on-device; offline expiry detection is real; revocation is "unchecked" unless online.
4. JIT is a guided handoff, never a fake toggle.
5. Repositories use AltSource v2 plus a safe extension namespace.
6. UI targets iOS 26 with availability fallbacks; localization and branding are first-class and runtime-configurable.
