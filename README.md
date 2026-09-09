# swift-palettecolor

**PaletteColor** is a Swift port of [AndroidX Palette](https://developer.android.com/reference/androidx/palette/graphics/Palette): it extracts a small set of representative swatches from an image (median-cut quantization over an RGB555 histogram), picks the six classic role swatches (`vibrant`, `darkVibrant`, `lightVibrant`, `muted`, `darkMuted`, `lightMuted`), and adds the WCAG contrast helpers you need to turn those swatches into a readable accent, wash and text scheme.

The quantizer, target scoring and default filter are ported from AndroidX Palette at commit [`81432a7d`](https://github.com/androidx/androidx/tree/81432a7d3a860faea8b18fb2a4712f1d6420f705/palette/palette/src/main/java/androidx/palette/graphics) and are kept integer/`Float` exact, so the same RGB888 pixel vector produces the same swatches on Android and Apple platforms.

- Pure Swift core (no UIKit/AppKit/SwiftUI required) — builds and tests on Linux
- `CGImage`, `UIImage`, `NSImage` and SwiftUI `Color` conveniences on Apple platforms
- iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+
- Apache-2.0

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/iheanyi/swift-palettecolor", from: "0.1.0"),
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

### Extract a palette from an image

```swift
import PaletteColor

// UIImage / NSImage / CGImage — the image is downscaled by area to 112×112
// (nearest neighbour, like Palette.Builder) before quantization.
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

`PaletteScheme` turns a palette into semantic roles: a three-stop background wash from the dark-muted and vibrant swatches, an accent pushed toward white (dark surfaces) or black (light surfaces) until it hits 4.5:1 against every wash stop, black-or-white `onAccent`, and primary/secondary text that stays readable on the wash. Extraction always includes the lightness-only retry.

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
| `Palette` | Result of extraction: `swatches`, `dominant`, `selected`, and `vibrant`/`darkVibrant`/`lightVibrant`/`muted`/`darkMuted`/`lightMuted`. `Palette.generate(pixels:maxColors:filter:retryLightnessOnly:)`, `Palette.generate(image:maxColors:filter:retryLightnessOnly:resizeArea:)` (CGImage/UIImage/NSImage), `Palette.pixels(from:resizeArea:)`. |
| `Palette.Swatch` | `rgb` (0xRRGGBB), `population`, `red`/`green`/`blue`, `hsl`, `color`, `swiftUIColor`. |
| `Palette.Target` | The six AndroidX targets with `saturationRange` and `lightnessRange`. |
| `Palette.Filter` | `.standard` (AndroidX `DEFAULT_FILTER`) or `.lightnessOnly`. |
| `HSL` | `ColorUtils.RGBToHSL`-compatible conversion. |
| `RGBColor` | sRGB color with `luminance`, `contrast(with:)`, `readable(on:minimum:)` (moves toward white or black, whichever the backgrounds need), `onColor`, `mixed(with:fraction:)`, `chroma`, packed `rgb`, and platform color conversions. |
| `PaletteScheme` | Semantic roles from a palette: `seed`, `darkMuted`, `vibrant`, `lightMuted`, `lightVibrant`, `washStops`, `accent`, `onAccent`, `primaryText`, `secondaryText`, `primaryContainer`, `secondaryContainer`, `surface`. `PaletteScheme(palette:)`, `PaletteScheme(pixels:)`, `PaletteScheme(image:)`, `.neutral`. |
| `PaletteScheme.Configuration` | `surface`, `fallbackAccent`, `onSurface`, `onSurfaceVariant`, `minimumContrast`, `minimumAccentChroma`. |

## Platform notes

The extraction core (`Palette`, `ColorCutQuantizer`, `HSL`, `RGBColor`, `PaletteScheme`) depends only on Foundation and runs anywhere Swift does. `Palette.pixels(from: CGImage)` and the `UIImage`/`NSImage`/`UIColor`/`NSColor`/SwiftUI conveniences are compiled only where those frameworks exist (`#if canImport(...)`). On Linux, `swift test` runs everything except the CoreGraphics-backed tests.

## Development

```sh
swift build
swift test
```

CI runs `swift test` on Ubuntu (Swift 5.10 and 6.1) and macOS, and builds the library for the iOS Simulator.

## License

Apache License 2.0 — see [LICENSE](LICENSE).

The palette extraction algorithm is derived from AndroidX Palette, Copyright 2018 The Android Open Source Project, also licensed under Apache 2.0. See [NOTICE](NOTICE) for the full attribution. The Swift port was originally written for [Camper](https://github.com/iheanyi/coda-android) and extracted into this package.
