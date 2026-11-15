# Importing files and JIT on iPadOS 26.6.1

This page records what DreamByte AppHub actually does for file import and what is
truthfully possible for JIT. It is written to be testable, not optimistic.

## Importing an IPA

AppHub accepts an IPA through four independent paths. Each one ends in the same
`AppPackageStore.importPackage` pipeline (copy, inspect, quarantine).

| Path | How |
|---|---|
| IPA Library | **Import IPA** button or the empty-state action |
| Dashboard | **Import IPA** shortcut |
| Files / share sheet | Share → **DreamByte AppHub**, or open the `.ipa` with AppHub |
| Files folder | Copy the `.ipa` into **On My iPad → DreamByte AppHub**, then open AppHub |

The fourth path needs no picker at all. AppHub scans its Documents folder at launch
and moves imported files to `Documents/Imported` so they are not imported twice.

### Why the picker used to fail

`UTType(filenameExtension: "ipa")` returns a *dynamic* type when no app declares
`.ipa`. Files can report an IPA as generic data or as a ZIP archive, and a picker
filtered to the dynamic type then greys the file out. The app now:

- declares `com.dreambyte.apphub.ipa` in `App/Info.plist` under
  `UTImportedTypeDeclarations`;
- declares a `CFBundleDocumentTypes` entry so open-in and the share sheet route to
  AppHub;
- includes `.data` in the picker's allowed types as a safety net, then validates
  the extension itself;
- shows picker failures instead of silently doing nothing;
- validates extension, file type, size, and iCloud download state before copying.

### Errors you may see

| Message key | Meaning |
|---|---|
| `ipa.wrongType` | The chosen file does not end in `.ipa` |
| `ipa.notAFile` | The chosen item is a folder or missing |
| `ipa.emptyFile` | The file has zero bytes |
| `ipa.cloudPlaceholder` | The file is still only in iCloud; download it in Files first |
| `ipa.importPickerFailed` | The document picker returned an error (details appended) |
| `ipa.inspectionFailed` | The file was copied but is not a valid IPA (for example, a ZIP renamed to `.ipa`) |

Renaming a ZIP to `.ipa` does not make it installable. The inspector checks for a
single `Payload/*.app` bundle with a readable `Info.plist`.

## JIT on iPadOS 26.6.1

**There is no dependable no-PC method on iPadOS 26.6.1.** This is not an AppHub
limitation; it is where the pairing requirement sits.

StikDebug enables JIT over the developer/debug interface. That requires a pairing
record (`pairing.plist`) that matches this iPad. On-device pairing was added in
**iOS/iPadOS 27** (StikPair requires iOS 27+, and the StikDebug guide says its
built-in pairing menu works on iOS/iPadOS 27+). On 26.6.1 the record has to be
created once by a host.

### Options, honestly ranked

1. **Update to iPadOS 27, then pair on-device.** StikDebug → Settings → Pair a
   Device → Pair iPhone or iPad. No computer.
   Caveat: SideStore's JIT documentation says iOS 26.6 and 27 only work with a
   limited set of apps. Confirm that your target app is supported before updating,
   and note that JIT is not guaranteed for every app.
2. **Create the pairing file once with a computer.** Use
   [iloader](https://iloader.app) or
   [idevice_pair](https://github.com/jkcoxson/idevice_pair), unlock and trust the
   iPad, then transfer the resulting pairing file to the iPad (AirDrop, Files, or
   the app's importer). Import it in StikDebug. After that, enabling JIT is
   on-device.
3. **Import an existing pairing file.** If you already have a valid
   `pairing.plist` for this iPad, AppHub can store it and StikDebug can use it.
   AppHub cannot create one.
4. **Jailbreak.** There is no current public jailbreak path for 26.6.1 that makes
   this simpler, and AppHub does not implement or recommend one.

### Requirements that are easy to miss

- **Developer Mode** must be enabled (Settings → Privacy & Security → Developer
  Mode), and the iPad must restart.
- **A loopback VPN** such as LocalDevVPN is needed so StikDebug can reach the
  device's debug service.
- **The target app must be signed with `get-task-allow`.** JIT attaches to a
  debuggable process. Many enterprise/ad-hoc profiles do not include that
  entitlement, so JIT will fail even with a correct pairing file.
- **AppHub itself does not use JIT.** Its JIT screen only stores the pairing file,
  checks prerequisites, and hands off to StikDebug. It cannot read another app's
  PID; iOS does not expose that.
- **No Apple credentials or private keys are requested.** AppHub does not bypass
  revocation, DNS, or OCSP checks.

### Recommended order

1. Fix import with the build that includes the UTI/document-type changes.
2. Enable Developer Mode and install LocalDevVPN.
3. Decide between iPadOS 27 on-device pairing and a one-time computer pairing.
4. Sign the target app with a profile that contains `get-task-allow`.
5. Import the pairing file into StikDebug (or let it create one on iPadOS 27).
6. Open StikDebug, select the target app, then return to AppHub and re-check.
