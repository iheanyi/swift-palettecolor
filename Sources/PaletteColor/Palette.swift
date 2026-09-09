// PaletteColor
// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 the swift-palettecolor authors. Licensed under the Apache License, Version 2.0.
//
// This file mirrors the AndroidX Palette defaults (Palette.java, Target.java). It intentionally
// keeps the implementation pure and integer based until HSL scoring, which makes the same ARGB
// pixel vector produce the same quantized swatches on Android and Apple platforms.
//
// Derived from AndroidX Palette (Apache License 2.0), Copyright 2018 The Android Open Source
// Project, androidx-main at 81432a7d3a860faea8b18fb2a4712f1d6420f705:
// palette/palette/src/main/java/androidx/palette/graphics/{Palette,ColorCutQuantizer,Target}.java
// See NOTICE for details.

import Foundation

/// Hue in degrees (`0..<360`), saturation and lightness in `0...1`, computed with the same `Float`
/// arithmetic as `androidx.core.graphics.ColorUtils.RGBToHSL`.
public struct HSL: Hashable, Sendable {
    public var hue: Float
    public var saturation: Float
    public var lightness: Float

    public init(hue: Float, saturation: Float, lightness: Float) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }

    /// Converts 8-bit RGB channels to HSL following `ColorUtils.RGBToHSL`.
    public init(red: Int, green: Int, blue: Int) {
        let r = Float(red) / 255
        let g = Float(green) / 255
        let b = Float(blue) / 255
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard delta != 0 else {
            self.init(hue: 0, saturation: 0, lightness: lightness)
            return
        }

        let saturation = lightness > 0.5
            ? delta / (2 - maximum - minimum)
            : delta / (maximum + minimum)
        let hue: Float
        if maximum == r {
            hue = (g - b) / delta + (g < b ? 6 : 0)
        } else if maximum == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        self.init(hue: hue * 60, saturation: saturation, lightness: lightness)
    }

    /// Converts an RGB888 value packed as `0xRRGGBB`.
    public init(rgb: UInt32) {
        self.init(red: Int((rgb >> 16) & 0xff), green: Int((rgb >> 8) & 0xff), blue: Int(rgb & 0xff))
    }
}

/// The result of AndroidX Palette–compatible color extraction: the quantized swatches, the most
/// populous swatch, and the swatch selected for each of the six default `Target` profiles.
public struct Palette: Hashable, Sendable {
    /// The six default AndroidX `Target` profiles with their saturation and lightness ranges.
    public enum Target: CaseIterable, Hashable, Sendable {
        case lightVibrant
        case vibrant
        case darkVibrant
        case lightMuted
        case muted
        case darkMuted

        /// `(minimum, target, maximum)` saturation, matching `Target.setDefaultVibrantSaturation`
        /// and `Target.setDefaultMutedSaturation`.
        public var saturationRange: (minimum: Float, target: Float, maximum: Float) {
            switch self {
            case .lightVibrant, .vibrant, .darkVibrant: return (0.35, 1, 1)
            case .lightMuted, .muted, .darkMuted: return (0, 0.3, 0.4)
            }
        }

        /// `(minimum, target, maximum)` lightness, matching `Target.setDefault{Light,Normal,Dark}LightnessValues`.
        public var lightnessRange: (minimum: Float, target: Float, maximum: Float) {
            switch self {
            case .lightVibrant, .lightMuted: return (0.55, 0.74, 1)
            case .vibrant, .muted: return (0.3, 0.5, 0.7)
            case .darkVibrant, .darkMuted: return (0, 0.26, 0.45)
            }
        }
    }

    /// A quantized color and the number of source pixels it represents.
    public struct Swatch: Hashable, Sendable {
        /// RGB888 packed as `0xRRGGBB`. AndroidX Palette's `Swatch` stores RGB with no alpha.
        public let rgb: UInt32
        public let population: Int

        public init(rgb: UInt32, population: Int) {
            self.rgb = rgb
            self.population = population
        }

        public var red: Int { Int((rgb >> 16) & 0xff) }
        public var green: Int { Int((rgb >> 8) & 0xff) }
        public var blue: Int { Int(rgb & 0xff) }
        public var hsl: HSL { HSL(red: red, green: green, blue: blue) }
        public var color: RGBColor { RGBColor(rgb: rgb) }
    }

    /// Controls which quantized colors are allowed to become swatches.
    public enum Filter: Hashable, Sendable {
        /// AndroidX `Palette.DEFAULT_FILTER`: rejects near-black, near-white and the red I-line.
        case standard
        /// Keeps only the lightness bounds of the default filter. Useful as a second pass when the
        /// standard filter rejects every color in an image (for example, mostly red artwork).
        case lightnessOnly

        public func allows(rgb: UInt32, hsl: HSL) -> Bool {
            switch self {
            case .standard:
                return hsl.lightness > 0.05 && hsl.lightness < 0.95
                    && !(hsl.hue >= 10 && hsl.hue <= 37 && hsl.saturation <= 0.82)
            case .lightnessOnly:
                return hsl.lightness > 0.05 && hsl.lightness < 0.95
            }
        }
    }

    /// Matches `Palette.Builder.DEFAULT_RESIZE_BITMAP_AREA`.
    public static let defaultResizeArea = 112 * 112
    /// Matches `Palette.Builder.DEFAULT_CALCULATE_NUMBER_COLORS`.
    public static let defaultColorCount = 16

    /// Every swatch produced by the quantizer, in quantizer order.
    public let swatches: [Swatch]
    /// The swatch with the largest population, if any.
    public let dominant: Swatch?
    /// The swatch chosen for each target that had a candidate in range.
    public let selected: [Target: Swatch]

    public init(swatches: [Swatch], dominant: Swatch?, selected: [Target: Swatch]) {
        self.swatches = swatches
        self.dominant = dominant
        self.selected = selected
    }

    /// A palette with no swatches.
    public static let empty = Palette(swatches: [], dominant: nil, selected: [:])

    public var isEmpty: Bool { swatches.isEmpty }

    public var lightVibrant: Swatch? { selected[.lightVibrant] }
    public var vibrant: Swatch? { selected[.vibrant] }
    public var darkVibrant: Swatch? { selected[.darkVibrant] }
    public var lightMuted: Swatch? { selected[.lightMuted] }
    public var muted: Swatch? { selected[.muted] }
    public var darkMuted: Swatch? { selected[.darkMuted] }

    public subscript(target: Target) -> Swatch? { selected[target] }

    /// Generates a palette from opaque RGB888 pixels packed as `0xRRGGBB` (higher bits are ignored).
    ///
    /// This is equivalent to `Palette.from(bitmap).maximumColorCount(maxColors).generate()` on
    /// Android for an already-resized bitmap. Use ``pixels(from:resizeArea:)`` to produce the
    /// pixel vector from a `CGImage` with the same area-based downscale the Android builder applies.
    ///
    /// - Parameter retryLightnessOnly: When `true` and `filter` rejects every color (for example,
    ///   mostly-red artwork under the standard filter's I-line rule), the extraction is run once
    ///   more with ``Filter/lightnessOnly`` so the image still yields swatches and roles.
    public static func generate(
        pixels: [UInt32],
        maxColors: Int = defaultColorCount,
        filter: Filter = .standard,
        retryLightnessOnly: Bool = false
    ) -> Palette {
        let palette = generateOnce(pixels: pixels, maxColors: maxColors, filter: filter)
        if retryLightnessOnly, palette.isEmpty, filter != .lightnessOnly {
            return generateOnce(pixels: pixels, maxColors: maxColors, filter: .lightnessOnly)
        }
        return palette
    }

    private static func generateOnce(pixels: [UInt32], maxColors: Int, filter: Filter) -> Palette {
        let swatches = ColorCutQuantizer.quantize(pixels: pixels, maxColors: maxColors, filter: filter)
        let dominant = swatches.max { $0.population < $1.population }
        var selected: [Target: Swatch] = [:]
        var used = Set<UInt32>()
        let maximumPopulation = dominant?.population ?? 1

        for target in Target.allCases {
            let saturation = target.saturationRange
            let lightness = target.lightnessRange
            var best: Swatch?
            var bestScore: Float = 0
            for swatch in swatches {
                let hsl = swatch.hsl
                guard hsl.saturation >= saturation.minimum && hsl.saturation <= saturation.maximum,
                      hsl.lightness >= lightness.minimum && hsl.lightness <= lightness.maximum,
                      !used.contains(swatch.rgb) else { continue }
                let score = 0.24 * (1 - abs(hsl.saturation - saturation.target))
                    + 0.52 * (1 - abs(hsl.lightness - lightness.target))
                    + 0.24 * (Float(swatch.population) / Float(maximumPopulation))
                if best == nil || score > bestScore {
                    best = swatch
                    bestScore = score
                }
            }
            if let best {
                selected[target] = best
                used.insert(best.rgb)
            }
        }
        return Palette(swatches: swatches, dominant: dominant, selected: selected)
    }
}
