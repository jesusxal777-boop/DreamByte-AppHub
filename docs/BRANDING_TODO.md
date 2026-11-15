# Replacing the placeholder branding

Everything visual is data. You do **not** need to touch view code.

## What is placeholder today

| Item | Current value | Where |
|---|---|---|
| Display name | `DreamByte AppHub` | `Core/Sources/AppHubCore/Branding/BrandTheme.swift` |
| Tagline | `App manager for iOS` | same |
| Wordmark text | `AppHub` | same |
| Palette | `#0A1A33`, `#2E7DFF`, `#5CC8FF` | same |
| Logo asset | `BrandMarkPlaceholder` (abstract bars) | `App/Sources/DreamByteAppHub/Resources/Assets.xcassets` |
| App icon | generated gradient with bars | `App/Sources/DreamByteAppHub/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` |

`BrandTheme.placeholder.isPlaceholder` is `true`, so Settings and the dashboard display a
"temporary branding" chip. Keep that flag until the official assets are approved.

## 1. Add the official assets

1. Drop the final app icon at `App/Sources/DreamByteAppHub/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
   (1024×1024, no transparency, no rounded corners — iOS masks it).
2. Add the logo as an image set, e.g.
   `App/Sources/DreamByteAppHub/Resources/Assets.xcassets/BrandMark.imageset/brandmark.png` (+ `@2x`, `@3x`).
3. Replace the `Contents.json` in that image set with the standard scale entries.

## 2. Point the theme at them

Edit `BrandTheme.placeholder` (or ship `branding.json`, see below):

```swift
logoAssetName: "BrandMark",
appIconAssetName: "AppIcon",
primaryHex: "#......",   // must be 6 or 8 hex digits
secondaryHex: "#......",
accentHex: "#......",
wordmarkText: "DreamByte",
displayName: "DreamByte AppHub",
isPlaceholder: false,    // only when the assets are final
```

## 3. Optional: override without rebuilding code

Drop a `branding.json` into the app bundle (`App/Sources/DreamByteAppHub/Resources/branding.json`) with any subset:

```json
{
  "displayName": "DreamByte AppHub",
  "wordmarkText": "DreamByte",
  "primaryHex": "#0A1A33",
  "secondaryHex": "#2E7DFF",
  "accentHex": "#5CC8FF",
  "logoAssetName": "BrandMark",
  "appIconAssetName": "AppIcon",
  "cornerRadius": 24,
  "usesLiquidGlass": true,
  "isPlaceholder": false
}
```

Missing fields keep their defaults; invalid hex strings and out-of-range corner radii are
ignored (see `BrandOverrides.applied(to:)`). `BrandLoader.loadFromBundle()` reads the
Core bundle first, then the app checks `Bundle.main` for `branding.json`.

## 4. Before shipping

- [ ] Official logo/wordmark/mascot received and approved by DreamByte Studios
- [ ] App icon exported for all required sizes (Xcode 26+: single 1024 icon is enough)
- [ ] Accent color matches the official palette (`Assets.xcassets/AccentColor.colorset`)
- [ ] Launch background updated (`LaunchBackground.colorset`)
- [ ] `isPlaceholder` set to `false`
- [ ] Screenshots refreshed with the final identity
- [ ] Trademark/attribution review completed

## Do not

- Do not ship the placeholder as if it were official artwork.
- Do not rename `BrandTheme` fields; third-party themes may rely on the JSON keys.
