// PaletteColor
// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 the swift-palettecolor authors. Licensed under the Apache License, Version 2.0.
//
// Twin of `MediaArtworkScheme` in iheanyi/coda-android (Camper Android): the Android SystemUI /
// UMP media-control accent recipe, built on Material Color Utilities `Style.CONTENT` rather than
// AndroidX Palette. See README "MediaArtworkScheme (SystemUI parity)" for the portable algorithm.

import Foundation

/// Semantic media colors derived from artwork the way Android SystemUI's media controls do:
/// Celebi quantization, Material `Score` seed selection with filtering disabled, and the
/// `SchemeContent` tonal palettes read at fixed dark-theme tones.
///
/// Unlike ``PaletteScheme``, low-chroma seeds are kept (a black-and-white cover yields a tone-90
/// grey accent, never a brand color), the roles come straight from HCT tonal palettes with no
/// WCAG push, and the only fallback is Google Blue when there are no pixels at all.
public struct MediaArtworkScheme: Hashable, Sendable {
    /// The `SchemeContent` tonal palette a role is read from.
    public enum PaletteRole: CaseIterable, Hashable, Sendable {
        /// `A1`: seed hue and chroma.
        case accent
        /// `A2`: seed hue, chroma reduced by 32 (never below half).
        case accentVariant
        /// `N1`: seed hue, chroma / 8.
        case neutral
        /// `N2`: seed hue, chroma / 8 + 4.
        case neutralVariant
    }

    /// `WallpaperColors.MAX_BITMAP_SIZE`: bitmaps with more pixels are downscaled to this area first.
    public static let maxBitmapArea = 112 * 112
    /// `GOOGLE_BLUE`, used only when the quantizer sees no pixels.
    public static let fallbackSeed = RGBColor(rgb: 0x1B6EF3)
    /// Material `Score.CUTOFF_CHROMA`: seeds below this are treated as monochrome by ``isChromatic``.
    public static let chromaCutoff: Double = 5

    /// The color the palettes are built from: the top `Score` result, or ``fallbackSeed``.
    public let seed: RGBColor
    /// The measured hue, chroma and tone of ``seed``.
    public let seedHCT: HCT
    /// Whether the seed has at least ``chromaCutoff`` chroma. `false` for black-and-white or grey
    /// artwork, whose roles are the mono recipe (tone-90 grey accent).
    public var isChromatic: Bool { seedHCT.chroma >= Self.chromaCutoff }

    /// `A1` tone 90. Play button, byline, waveform and notification accent.
    public let accent: RGBColor
    /// `N1` tone 10. Content drawn on ``accent``.
    public let onAccent: RGBColor
    /// `A1` tone 80.
    public let accentSecondary: RGBColor
    /// `N1` tone 95.
    public let textPrimary: RGBColor
    /// `N2` tone 80.
    public let textSecondary: RGBColor
    /// `N2` tone 60.
    public let textTertiary: RGBColor
    /// `A2` tone 20.
    public let surface: RGBColor
    /// `A2` tone 30. Scrim over artwork behind the surface.
    public let scrimSurface: RGBColor
    /// `A1` tone 30. Accent-tinted scrim.
    public let scrimAccent: RGBColor

    /// Builds the `SchemeContent` dark palettes from `seed` and reads the media roles from them.
    public init(seed: RGBColor) {
        let hct = HCT(seed)
        self.seed = seed
        self.seedHCT = hct
        func palette(_ role: PaletteRole) -> TonalPalette {
            TonalPalette.of(hct.hue, Self.chroma(of: role, seedChroma: hct.chroma))
        }
        let a1 = palette(.accent)
        let a2 = palette(.accentVariant)
        let n1 = palette(.neutral)
        let n2 = palette(.neutralVariant)
        accent = Self.color(a1.tone(90))
        onAccent = Self.color(n1.tone(10))
        accentSecondary = Self.color(a1.tone(80))
        textPrimary = Self.color(n1.tone(95))
        textSecondary = Self.color(n2.tone(80))
        textTertiary = Self.color(n2.tone(60))
        surface = Self.color(a2.tone(20))
        scrimSurface = Self.color(a2.tone(30))
        scrimAccent = Self.color(a1.tone(30))
    }

    /// Quantizes already-downscaled opaque RGB888 pixels (`0xRRGGBB`, higher bits ignored), scores
    /// a seed and builds the scheme. Use ``init(pixels:width:height:)`` or an image initializer
    /// when the source has not been reduced to ``maxBitmapArea`` yet.
    public init(pixels: [UInt32]) {
        self.init(seed: Self.seedColor(pixels: pixels))
    }

    /// Downscales a `width` × `height` RGB888 bitmap like `WallpaperColors.fromBitmap`, then
    /// quantizes and scores it. `pixels` is row-major and must hold `width * height` values.
    public init(pixels: [UInt32], width: Int, height: Int) {
        self.init(pixels: Self.downscaled(pixels: pixels, width: width, height: height))
    }

    /// A muted neutral for players with no artwork, built the way Android's `MissingArtwork` is:
    /// `fromSeed(Hct(brandHue, brandChroma / 8, 50))`. The package does not import brand
    /// constants, so the seed is a cool (cyan-family) hue at chroma 4 — below ``chromaCutoff``,
    /// so ``isChromatic`` is `false` — giving a tone-90 muted grey accent, never a vivid color.
    /// Seed your own launcher or brand-neutral color through ``init(seed:)`` to override it.
    public static let missingArtwork = MediaArtworkScheme(seed: HCT(hue: 209, chroma: 4, tone: 50).color)

    /// Any tone of any of the four palettes, for states the fixed roles do not cover.
    public func tone(_ tone: Double, of role: PaletteRole) -> RGBColor {
        HCT(hue: seedHCT.hue, chroma: Self.chroma(of: role, seedChroma: seedHCT.chroma), tone: tone).color
    }

    /// The `CorePalettesContent` chroma of each palette for a seed of `seedChroma`.
    static func chroma(of role: PaletteRole, seedChroma: Double) -> Double {
        switch role {
        case .accent: return seedChroma
        case .accentVariant: return max(seedChroma - 32, seedChroma * 0.5)
        case .neutral: return seedChroma / 8
        case .neutralVariant: return seedChroma / 8 + 4
        }
    }

    // MARK: Seed selection

    /// `QuantizerCelebi` at ``maxColors(forArea:)`` followed by `Score.score(desired: 4,
    /// fallback: GOOGLE_BLUE, filter: false)`. Grey seeds are kept; the fallback is used only when
    /// `pixels` is empty.
    public static func seedColor(pixels: [UInt32]) -> RGBColor {
        let argbPixels = pixels.map(argb(fromRGB:))
        let quantized = QuantizerCelebi().quantize(argbPixels, maxColors(forArea: pixels.count))
        let ranked = Score.score(
            quantized.colorToCount,
            desired: 4,
            fallbackColorARGB: argb(fromRGB: fallbackSeed.rgb),
            filter: false
        )
        return color(ranked[0])
    }

    /// `clamp(area / 16, 5, 128)` quantizer clusters for a bitmap of `area` pixels.
    public static func maxColors(forArea area: Int) -> Int {
        min(128, max(5, area / 16))
    }

    /// Nearest-neighbour downscale to at most ``maxBitmapArea`` pixels, matching
    /// `WallpaperColors.calculateOptimalSize` (scale by `sqrt(max / area)`, truncate, minimum 1)
    /// and `Bitmap.createScaledBitmap(filter = false)`. Bitmaps at or under the limit are returned
    /// unchanged.
    public static func downscaled(pixels: [UInt32], width: Int, height: Int, maxArea: Int = maxBitmapArea) -> [UInt32] {
        precondition(pixels.count == width * height, "pixels must hold width * height values")
        guard let size = scaledSize(width: width, height: height, maxArea: maxArea) else { return pixels }
        var result = [UInt32]()
        result.reserveCapacity(size.width * size.height)
        for y in 0..<size.height {
            let sourceY = min(height - 1, Int((Double(y) + 0.5) * Double(height) / Double(size.height)))
            let row = sourceY * width
            for x in 0..<size.width {
                let sourceX = min(width - 1, Int((Double(x) + 0.5) * Double(width) / Double(size.width)))
                result.append(pixels[row + sourceX])
            }
        }
        return result
    }

    /// The `WallpaperColors.calculateOptimalSize` target, or `nil` when no downscale is needed.
    static func scaledSize(width: Int, height: Int, maxArea: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0, width * height > maxArea else { return nil }
        let scale = (Double(maxArea) / Double(width * height)).squareRoot()
        return (max(1, Int(Double(width) * scale)), max(1, Int(Double(height) * scale)))
    }

    // MARK: ARGB bridging

    static func argb(fromRGB rgb: UInt32) -> Int {
        Int(0xFF00_0000 | (rgb & 0x00FF_FFFF))
    }

    static func rgb(fromARGB argb: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: argb) & 0x00FF_FFFF
    }

    static func color(_ argb: Int) -> RGBColor {
        RGBColor(rgb: rgb(fromARGB: argb))
    }
}
