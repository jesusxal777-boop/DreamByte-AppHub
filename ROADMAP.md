# DreamByte AppHub — Roadmap

Status legend: ✅ done & tested · 🟡 implemented, not testable here · 🔵 in progress · ⬜ planned · ⛔ blocked by platform

## Phase 1 — Research (✅)

- [x] Audit Linux host (OS, Swift, SDKs, xtool, disk, device tooling)
- [x] Apple signing architecture and free-account limits
- [x] Installation mechanisms and public-API limits
- [x] JIT mechanisms for iOS 26 (StikDebug / TXM protocol)
- [x] AltSource v2 repository format
- [x] SwiftUI Liquid Glass APIs
- [x] Deliverables: `RESEARCH.md`, `FEASIBILITY.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `TECH_STACK.md`

## Phase 2 — Architecture (✅)

- [x] Two-package design (`AppHubCore` testable on Linux, `AppHubApp` iOS UI)
- [x] Module boundaries and dependency graph
- [x] Security boundaries for untrusted archives
- [x] Localization and branding as data
- [x] Build/signing strategy documented

## Phase 3 — Prototype / foundation (✅)

- [x] Repository skeleton and build scripts
- [x] Design system tokens and temporary branding
- [x] Four-language localization system (runtime switching)
- [x] SwiftUI navigation shell (iPhone tabs, iPad split view)
- [ ] iPhone/iPad visual verification (⛔ needs iOS SDK)

## Phase 4 — Core engines (🔵)

- [x] ZIP reader with ZIP64, CRC, traversal and bomb limits
- [x] IPA inspector (Info.plist, Mach-O architectures, encryption, signature presence)
- [x] SHA-256 and CRC-32 in pure Swift
- [x] AltSource v2 repository engine with validation and caching
- [x] File-backed IPA library store
- [x] Download engine with progress/cancel/validation (tested end-to-end on Linux)
- [x] Provisioning profile inspection (dates, team, entitlements, devices)
- [x] X.509 certificate reader (CN, validity, SHA-256 fingerprint)
- [x] Diagnostics report builder with redaction
- [ ] Download resume across app relaunches (⬜ not implemented; interrupted jobs fail honestly)

## Phase 5 — iOS integration (🔵)

- [x] Document import and security-scoped copies (✅ declared `.ipa` UTI, document types, open-in, tolerant picker, Documents-folder fallback; runtime unverified)
- [x] Keychain-backed p12 import adapter (🟡 Apple-only)
- [x] StikDebug handoff + prerequisite checks (🟡 device-only)
- [x] App library: AppHub-managed records + honest unavailable state (🟡 private enumeration deferred)
- [x] Share/export flows
- [x] OTA installation handoff (`manifest.plist` generation + `itms-services://`) (🟡 device-only verification)
- [x] Selectable installation modes with an honest availability planner (OTA, local signing, device bridge, external tool) (🟡 type-checked, not run)
- [x] JIT pairing-requirement matrix documented (✅ on-device pairing needs iPadOS 27; 26.6.1 needs a one-time computer)
- [ ] Local on-device signing pipeline (Mach-O re-sign + CMS/PKCS#7) (⬜)
- [ ] Real device installation bridge (pairing + loopback + installation_proxy) (⬜)
- [ ] Built-in StikJIT helper (⬜, AGPL + Xcode required)

## Phase 6 — Testing (🔵)

- [x] Automated core test suite with IPA/repository/profile fixtures (96 tests, 0 failures on Swift 6.0.3/Linux)
- [x] Localization parity test across es/en/fr/pt
- [x] App package manifest valid; `AppHubCore` compiles inside the App target on Linux
- [x] GitHub Actions workflow for an unsigned IPA on macOS (✅ run #43702717542 passed)
- [x] SwiftUI compiles and links for iOS on GitHub Actions (macOS 15, Xcode 16.4) (🟡 Liquid Glass path not compiled)
- [ ] Device tests on iOS 26/27 (⛔ no device attached)
- [x] Document untested areas explicitly

## Phase 7 — Release preparation (⬜)

- [ ] Final branding assets from DreamByte Studios
- [ ] Bundle identifier and signing team
- [ ] App icon set from official artwork
- [ ] Privacy policy and license decision
- [ ] TestFlight/adhoc or sideload distribution plan
- [ ] On-device installation and JIT validation

## Immediate next steps

1. ~~Compile and test `Core` on Linux (`swift test`).~~ Done: Swift 6.0.3, 90/90 passing.
2. ~~Resolve Swift 6 concurrency diagnostics.~~ Done.
3. When macOS/Xcode 26+ is available: build `App`, fix API availability issues, capture iPhone/iPad screenshots.
4. Obtain a device + Apple ID to validate signing/install/JIT flows.
5. Design and implement the device bridge only after those validations.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| No iOS SDK on Linux | UI unverified | Keep UI thin over tested core; provide Xcode build instructions |
| iOS 26/27 API changes | Compile breaks | Availability gates; deployment target 18 |
| Free-account 7-day expiry | Poor UX | Expiry countdown + re-sign guidance; document limits |
| JIT fragility per OS build | Feature outages | Honest status, handoff to maintained StikDebug |
| Private APIs | Distribution risk | Off by default, clearly labeled, never in App Store build |
| Branding absent | Visual placeholders | Data-driven `BrandTheme`, one-file replacement |
