# swift-palettecolor

**PaletteColor** turns artwork into UI colors two ways:

- **`MediaArtworkScheme`** — the Android SystemUI / UMP media-control recipe: Material Color Utilities `Style.CONTENT` (Celebi quantizer → `Score` → HCT tonal palettes). This is the source of truth shared with Camper Android's `MediaArtworkScheme`; use it for Now Playing accents, bylines, waveforms and notifications.
- **`Palette` / `PaletteScheme`** — a Swift port of [AndroidX Palette](https://developer.android.com/reference/androidx/palette/graphics/Palette): median-cut quantization over an RGB555 histogram, the six classic role swatches (`vibrant`, `darkVibrant`, `lightVibrant`, `muted`, `darkMuted`, `lightMuted`), and WCAG contrast helpers that turn those swatches into a readable accent, wash and text scheme.

The AndroidX quantizer, target scoring and default filter are ported from AndroidX Palette at commit [`81432a7d`](https://github.com/androidx/androidx/tree/81432a7d3a860faea8b18fb2a4712f1d6420f705/palette/palette/src/main/java/androidx/palette/graphics) and are kept integer/`Float` exact, so the same RGB888 pixel vector produces the same swatches on Android and Apple platforms. The HCT/CAM16 solver, Celebi quantizer, `Score` and `TonalPalette` are vendored from [material-color-utilities](https://github.com/material-foundation/material-color-utilities) at commit [`5b3618b`](https://github.com/material-foundation/material-color-utilities/tree/5b3618b16fdc3825e21d5679bafd144662088ea1/swift) (see [Vendored Material Color Utilities](#vendored-material-color-utilities)).

- Pure Swift core (no UIKit/AppKit/SwiftUI required) — builds and tests on Linux
- `CGImage`, `UIImage`, `NSImage` and SwiftUI `Color` conveniences on Apple platforms
- iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+
- Apache-2.0

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/iheanyi/swift-palettecolor", from: "0.2.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "PaletteColor", package: "swift-palettecolor"),
        ]
    ),
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and enter `https://github.com/iheanyi/swift-palettecolor`.

## Quick usage

### MediaArtworkScheme (SystemUI parity)

```swift
import PaletteColor

// UIImage / NSImage / CGImage. UIImages are redrawn orientation-correct first, then the
// bitmap is downscaled like WallpaperColors.fromBitmap (nearest neighbour to ≤ 112×112 pixels).
let scheme = MediaArtworkScheme(image: artwork) ?? .missingArtwork

scheme.accent           // Play button, byline, waveform, notification accent (A1 tone 90)
scheme.onAccent         // content on the accent (N1 tone 10)
scheme.accentSecondary  // A1 tone 80
scheme.textPrimary      // N1 tone 95
scheme.textSecondary    // N2 tone 80
scheme.textTertiary     // N2 tone 60
scheme.surface          // A2 tone 20
scheme.seed             // the scored seed color; scheme.seedHCT has its hue/chroma/tone
scheme.tone(70, of: .accent)  // any other tone of the A1/A2/N1/N2 palettes

// Already have RGB888 pixels (custom decoder, Linux)? Pass the bitmap so the same downscale runs:
let fromPixels = MediaArtworkScheme(pixels: pixels, width: width, height: height)
// Or seed directly (for example, from a launcher / brand-neutral color when there is no artwork):
let seeded = MediaArtworkScheme(seed: RGBColor(rgb: 0x5B5E66))
```

The algorithm is the portable SoT shared with Camper Android's `MediaArtworkScheme` and is implemented exactly:

1. **Downscale** like `WallpaperColors.fromBitmap`: if `w * h > 112 * 112`, nearest-neighbour scale to area `112 * 112` (dimensions truncated, minimum 1).
2. **Quantize** with `QuantizerCelebi` (Wu + weighted-square-means in L\*a\*b\*), `maxColors = clamp(area / 16, 5, 128)`.
3. **Seed** = `Score.score(colorToPopulation, desired: 4, fallback: 0xFF1B6EF3 /* GOOGLE_BLUE */, filter: false)[0]`. Filtering is off, so low-chroma seeds are **kept** (mono artwork gets the mono recipe); Google Blue is used only when the quantizer sees no pixels at all.
4. **`SchemeContent` palettes** (dark, contrast 0): `A1 = TonalPalette(h, c)`, `A2 = TonalPalette(h, max(c − 32, 0.5c))`, `N1 = TonalPalette(h, c / 8)`, `N2 = TonalPalette(h, c / 8 + 4)`.
5. **Roles**: `accent = A1.tone(90)`, `onAccent = N1.tone(10)`, `accentSecondary = A1.tone(80)`, `textPrimary = N1.tone(95)`, `textSecondary = N2.tone(80)`, `textTertiary = N2.tone(60)`, `surface = A2.tone(20)`.

Behaviour this locks in:

- The byline uses `scheme.accent` for every cover, including monochrome ones, where it is a tone-90 grey — never a brand cyan.
- There is no WCAG push and no chroma floor: tones come straight from HCT, so accents stay muted, UMP-style, and a black-and-white cover produces a grey scheme with the same formula.
- `MediaArtworkScheme.missingArtwork` is a muted cool grey (seed HCT `260 / 8 / 40`) for players with no artwork. If your product has a launcher or brand-neutral seed, build it with `MediaArtworkScheme(seed:)` instead; do not fall back to a loud accent like `#6FD8E8` for these roles.

#### `MediaArtworkScheme` vs `PaletteScheme`

| | `MediaArtworkScheme` | `PaletteScheme` |
| --- | --- | --- |
| Source of truth | Android SystemUI media controls / UMP (`ColorScheme`, `Style.CONTENT`) | AndroidX `Palette` + Camper's original WCAG scheme |
| Downscale | `WallpaperColors`: area 112², truncate | `Palette.Builder`: area 112², ceil |
| Quantizer | `QuantizerCelebi` (Wu → k-means in Lab), 5–128 clusters | `ColorCutQuantizer` (median cut over RGB555), 16 swatches |
| Seed | `Score` (hue-proportion + chroma), filter off | light-vibrant → light-muted → vibrant → dominant |
| Grey artwork | Grey scheme (accent = tone-90 grey) | `fallbackAccent` (cyan by default) |
| Roles | Fixed HCT tones from `SchemeContent` palettes | Accent/text pushed to ≥ 4.5:1 against a wash gradient |
| Fallback | `GOOGLE_BLUE` seed, only for empty input | `nil` when the palette is empty |

Both pipelines share `RGBColor` and the platform image helpers, so you can run them side by side.

### HCT

`HCT` is a small value type over the vendored HCT solver, for callers who need Material tones without going through a scheme:

```swift
let hct = HCT(RGBColor(rgb: 0x2070D8))      // measure: hue 264.3, chroma 60.6, tone 48.1
HCT(hue: hct.hue, chroma: hct.chroma, tone: 90).color   // solve back to sRGB (chroma clamped to gamut)
```

### Extract a palette from an image

```swift
import PaletteColor

// UIImage / NSImage / CGImage — the image is downscaled by area to 112×112
// (nearest neighbour, like Palette.Builder) before quantization. UIImages are
// first redrawn orientation-correct (EXIF rotation/mirroring applied) instead of
// reading the raw `cgImage`.
// `retryLightnessOnly` reruns with a lightness-only filter if AndroidX's default
// filter rejects every color (mostly-red artwork), so roles are still produced.
guard let palette = Palette.generate(image: artwork, retryLightnessOnly: true) else { return }

palette.vibrant?.rgb          // 0xRRGGBB packed
palette.darkMuted?.color      // RGBColor with Double channels
palette.dominant?.population  // pixel count behind the most populous swatch
palette.swatches              // every swatch the quantizer produced

// Match AndroidX's `Palette.from(bitmap).maximumColorCount(24)`
let detailed = Palette.generate(image: artwork, maxColors: 24)
```

If you already have opaque RGB888 pixels (for example, from your own decoder or on Linux), skip the image step:

```swift
let pixels: [UInt32] = [0x2070D8, 0x2070D8, 0xD020C0, 0x5C8A60, /* … */]
let palette = Palette.generate(pixels: pixels)
```

### Filters

`Palette.Filter.standard` is AndroidX's `DEFAULT_FILTER` (rejects near-black, near-white and the red I-line). Images that are mostly red can yield no swatches under that filter. Pass `retryLightnessOnly: true` to any `generate` call to run one more pass with `.lightnessOnly` (only the lightness bounds) when the first pass comes back empty; `PaletteScheme` always does this.

```swift
let palette = Palette.generate(pixels: pixels, retryLightnessOnly: true)
let fromImage = Palette.generate(image: artwork, retryLightnessOnly: true)
```

With the default `retryLightnessOnly: false`, `Palette.generate` behaves exactly like AndroidX and may return an empty palette.

### Build a readable color scheme

`PaletteScheme` turns a palette into semantic roles: a three-stop background wash from the dark-muted and vibrant swatches, an accent pushed toward white (dark surfaces) or black (light surfaces) until it hits 4.5:1 against every wash stop, black-or-white `onAccent`, and primary/secondary text roles that are pushed the same way whenever the configured neutrals fall short on a wash stop. Extraction always includes the lightness-only retry.

```swift
let scheme = PaletteScheme(image: artwork) ?? .neutral

scheme.washStops        // [RGBColor] — top-to-bottom gradient stops ending on the surface
scheme.accent           // ≥ 4.5:1 against every wash stop
scheme.onAccent         // .black or .white
scheme.primaryText
scheme.secondaryText
scheme.primaryContainer
scheme.secondaryContainer

// SwiftUI
LinearGradient(
    colors: scheme.washStops.map(Color.init),
    startPoint: .top, endPoint: .bottom
)
Button("Play") { … }.tint(scheme.accent.color)
```

The surface, fallback accent, neutral text roles and contrast threshold are all parameters. The defaults describe a dark surface with Material-style neutrals; pass your own to match your theme, including light ones:

```swift
let light = PaletteScheme.Configuration(
    surface: .white,
    fallbackAccent: RGBColor(rgb: 0x0077AA),
    onSurface: RGBColor(rgb: 0x1B1B1F),
    onSurfaceVariant: RGBColor(rgb: 0x46464F),
    minimumContrast: 4.5,      // 7 for WCAG AAA
    minimumAccentChroma: 0.04  // greyer control seeds use fallbackAccent
)
let scheme = PaletteScheme(image: artwork, configuration: light)
```

### Contrast helpers

`RGBColor` is a plain sRGB value type with the math you need for accessible palette-derived UI:

```swift
let accent = RGBColor(rgb: 0x2070D8)
accent.luminance                       // WCAG relative luminance
accent.contrast(with: .black)          // WCAG contrast ratio
accent.readable(on: [surface], minimum: 4.5)  // push toward white or black until readable
accent.onColor                         // .black or .white
accent.mixed(with: .white, fraction: 0.2)
accent.chroma
accent.color / accent.uiColor / accent.nsColor / accent.cgColor
```

## Public API

| Type | Purpose |
| --- | --- |
| `MediaArtworkScheme` | SystemUI/UMP media accent scheme: `seed`, `seedHCT`, `accent`, `onAccent`, `accentSecondary`, `textPrimary`, `textSecondary`, `textTertiary`, `surface`, `tone(_:of:)`. `MediaArtworkScheme(seed:)`, `MediaArtworkScheme(pixels:)`, `MediaArtworkScheme(pixels:width:height:)`, `MediaArtworkScheme(image:)` (CGImage/UIImage/NSImage), `.missingArtwork`, `.fallbackSeed`, `.maxBitmapArea`, `seedColor(pixels:)`, `maxColors(forArea:)`, `downscaled(pixels:width:height:)`, `pixels(from:)` (CGImage/UIImage). |
| `MediaArtworkScheme.PaletteRole` | `.accent` (A1), `.accentVariant` (A2), `.neutral` (N1), `.neutralVariant` (N2). |
| `HCT` | Material HCT value type: `hue`, `chroma`, `tone`; `HCT(_ color:)` / `HCT(rgb:)` measure, `color` solves to sRGB. |
| `Palette` | Result of extraction: `swatches`, `dominant`, `selected`, and `vibrant`/`darkVibrant`/`lightVibrant`/`muted`/`darkMuted`/`lightMuted`. `Palette.generate(pixels:maxColors:filter:retryLightnessOnly:)`, `Palette.generate(image:maxColors:filter:retryLightnessOnly:resizeArea:)` (CGImage/UIImage/NSImage), `Palette.pixels(from:resizeArea:)` (CGImage/UIImage). |
| `Palette.Swatch` | `rgb` (0xRRGGBB), `population`, `red`/`green`/`blue`, `hsl`, `color`, `swiftUIColor`. |
| `Palette.Target` | The six AndroidX targets with `saturationRange` and `lightnessRange`. |
| `Palette.Filter` | `.standard` (AndroidX `DEFAULT_FILTER`) or `.lightnessOnly`. |
| `HSL` | `ColorUtils.RGBToHSL`-compatible conversion. |
| `RGBColor` | sRGB color with `luminance`, `contrast(with:)`, `readable(on:minimum:)` (moves toward white or black, whichever the backgrounds need), `onColor`, `mixed(with:fraction:)`, `chroma`, packed `rgb`, and platform color conversions. |
| `PaletteScheme` | Semantic roles from a palette: `seed`, `darkMuted`, `vibrant`, `lightMuted`, `lightVibrant`, `washStops`, `accent`, `onAccent`, `primaryText`, `secondaryText`, `primaryContainer`, `secondaryContainer`, `surface`. `PaletteScheme(palette:)`, `PaletteScheme(pixels:)`, `PaletteScheme(image:)`, `.neutral`. |
| `PaletteScheme.Configuration` | `surface`, `fallbackAccent`, `onSurface`, `onSurfaceVariant`, `minimumContrast`, `minimumAccentChroma`. |

## Platform notes

The extraction core (`Palette`, `ColorCutQuantizer`, `HSL`, `RGBColor`, `PaletteScheme`, `MediaArtworkScheme`, `HCT`) depends only on Foundation and runs anywhere Swift does. `Palette.pixels(from: CGImage)`, `MediaArtworkScheme.pixels(from: CGImage)` and the `UIImage`/`NSImage`/`UIColor`/`NSColor`/SwiftUI conveniences are compiled only where those frameworks exist (`#if canImport(...)`). On Linux, `swift test` runs everything except the CoreGraphics- and UIKit-backed tests.

On UIKit platforms, `UIImage` inputs go through `UIImage.paletteNormalizedCGImage()`: images that are already `.up` and CGImage-backed are used directly, everything else is redrawn at native pixel size with `UIGraphicsImageRenderer` so `imageOrientation` is honoured (on watchOS, where the renderer is unavailable, the raw `cgImage` is used). Both `Palette` and `MediaArtworkScheme` use this path.

### Vendored Material Color Utilities

`Sources/PaletteColor/MaterialColorUtilities/` is a copy of the HCT/CAM16 solver, `QuantizerCelebi` (Wu + Wsmeans), `Score` and `TonalPalette` from the official Swift port of [material-color-utilities](https://github.com/material-foundation/material-color-utilities) at commit `5b3618b`. It is vendored rather than declared as a dependency because the Swift package lives in a subdirectory of an untagged monorepo, which SwiftPM cannot reference. The copy is kept `internal` so an app that also depends on `MaterialColorUtilities` directly gets no duplicate symbols; `HCT` and `MediaArtworkScheme` are the public surface. Local edits are limited to access control, removing a debug static that is not concurrency-safe, and warning fixes — see [NOTICE](NOTICE).

## Development

```sh
swift build
swift test
```

CI runs `swift test` on Ubuntu (Swift 5.10 and 6.1) and macOS, and runs the test bundle on the iOS Simulator to cover the UIKit paths.

## License

Apache License 2.0 — see [LICENSE](LICENSE).

The palette extraction algorithm is derived from AndroidX Palette, Copyright 2018 The Android Open Source Project, and the HCT/quantizer/scoring code is derived from Material Color Utilities, Copyright 2023 Google LLC — both also licensed under Apache 2.0. See [NOTICE](NOTICE) for the full attribution. The Swift port was originally written for [Camper](https://github.com/iheanyi/coda-android) and extracted into this package.
