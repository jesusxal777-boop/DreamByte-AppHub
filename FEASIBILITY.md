# DreamByte AppHub — Feasibility Matrix

Legend:
**A** Fully feasible with public APIs · **B** Feasible with limitations · **C** Requires external tools/device · **D** Requires macOS/Xcode · **E** Not possible through public APIs

| # | Feature | Class | What is genuinely deliverable | Hard limits |
|---|---|---|---|---|
| A1 | Import IPA files | **A** | Document picker, security-scoped copy, quarantine, sandbox storage | None |
| A2 | Inspect IPA metadata | **A** | Bundle ID, name, versions, min OS, architectures, icon, signature presence, encryption flag, CRC/integrity errors | Malformed/adversarial ZIPs need hardened limits |
| A3 | Manage imported IPAs | **A** | List, rename, delete, export, storage usage | None |
| A4 | Detect corrupted/incompatible packages | **A** | ZIP structure, CRC, Info.plist, Mach-O arch/min-OS checks | Cannot prove Apple signature trust offline |
| A5 | Install IPA via OTA | **B** | Generate a correct `manifest.plist` and open `itms-services://` links; iOS performs the install | Needs a **signed** IPA (enterprise/ad-hoc/development) hosted over HTTPS; AppHub cannot confirm the result and does not sign or host |
| A5b | On-device signing | **C** | Future module: zsign-style Mach-O re-sign + CMS with a user-imported identity | Needs PKCS#7 signing, entitlements rewriting, and a working install path; high complexity |
| A5c | Anti-revoke DNS profiles | **E (refused)** | Documented as unsafe and deliberately not implemented | Bypasses Apple revocation/OCSP; security and Terms-of-Service violation |
| B1 | Import certificates/profiles | **B** | `.mobileprovision` inspection; `.p12` import with password into Keychain (Apple) | p12 needs Security.framework; unavailable on Linux tests |
| B2 | Display expiry/signing info | **A/B** | Profile dates, team, app ID, entitlements, device count, cert subject/validity | Certificate chain/trust evaluation needs Apple trust store |
| B3 | Detect expired/revoked | **B** | Expiry: exact, offline. Revocation: only with network OCSP/CRL; otherwise "not checked" | Offline revocation cannot be guaranteed |
| B4 | Public certificate compatibility | **E** | Explain why public/shared certs are unsafe and often revoked | Apple intentionally blocks shared cert abuse |
| C1 | JIT availability UI | **A** | Device/OS, `get-task-allow`, pairing file presence, StikDebug handoff status | Cannot read another process's JIT flag reliably |
| C2 | Activate JIT | **C** | Deep link to StikDebug (verified scheme) + step-by-step guidance | Requires pairing file, loopback VPN, Developer Mode, matching script; iOS 26 TXM protocol |
| C3 | Built-in JIT | **C/D** | Optional later via StikJIT helper extension | Needs Xcode, extension, AGPL compliance, per-OS scripting; not testable here |
| D1 | Add/browse repositories | **A** | AltSource v2 fetch, validation, cache, ETag, refresh, error states | Server CORS irrelevant (native); TLS required by ATS |
| D2 | Custom extensible format | **A** | `apphub` namespace + tolerant decoding | Must not break AltStore clients |
| E1 | List installed apps | **B/E** | Only AppHub-managed records + honest "unavailable" state by default | App Store-safe apps cannot enumerate all installed apps; private `LSApplicationWorkspace` is not App Store-safe |
| E2 | Updates/signing info | **B** | Compare installed AppHub record version to repo version; signing info from imported IPA | Detecting updates for apps installed by other means is not generally possible |
| F1 | Download IPA | **A** | Background-capable URLSession download, progress, cancel, resume data, size/SHA-256 validation | Network conditions; no silent execution |
| F2 | Validate downloads | **A** | Size, SHA-256 (optional manifest), IPA structural inspection, quarantine | Publisher signatures need a trust model |
| G1 | Device/application diagnostics | **A/B** | OS, model, disk, locale, app config, IPA/repo/signing/JIT states, JSON export | Some identifiers restricted by Apple |
| H1 | Liquid Glass UI | **D** | Complete SwiftUI implementation with iOS 26 APIs + fallbacks | Compilation needs iOS 26 SDK (Xcode 27.1) |
| H2 | Localization es/en/fr/pt | **A** | Runtime switch, first-launch detection, persisted override, key-parity tests | None |
| H3 | Branding placeholders | **A** | Configurable theme, asset names, generated placeholder icon, no final identity | Final assets pending from DreamByte Studios |
| I1 | On-device install bridge | **C** | Future module: pairing file + loopback bridge + installation_proxy | Requires device, signing identity, VPN, high complexity |

## Non-negotiable honesty rules

- A disabled button with an explanation is acceptable. A fake success is not.
- "Install" never reports success; OTA installation is handed to iOS, whose prompt and result AppHub cannot observe. A future `installation_proxy` bridge would only report success on a real successful call.
- Anti-revoke DNS profiles, certificate sharing, and revocation bypasses are out of scope by design.
- "JIT enabled" is only shown after the app's own readiness check (and, on TXM devices, the script protocol), never after merely opening StikDebug.
- "Certificate valid" means dates and structure passed; revocation displays as `unchecked` unless an online check succeeded.
- "App library" shows AppHub-managed apps; system-wide enumeration is marked unavailable unless a private-API build is explicitly enabled.

## What can be verified on this Linux host

| Area | Verification |
|---|---|
| IPAEngine, repository, downloads, SHA-256, localization, diagnostics | `swift test` on Linux with fixtures |
| Localization coverage | Automated key-parity + placeholder test across es/en/fr/pt |
| SwiftUI screens | Source review only; requires Xcode 27.1 to compile |
| Certificate p12 import | Requires Apple Security.framework; parser tests use synthetic profiles |
| Device install / JIT | Requires physical device + signing identity; not testable here |
