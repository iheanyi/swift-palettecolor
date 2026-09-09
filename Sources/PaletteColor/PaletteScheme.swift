// PaletteColor
// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 the swift-palettecolor authors. Licensed under the Apache License, Version 2.0.

import Foundation

/// Semantic color roles derived from a ``Palette``: a background wash built from the dark-muted
/// and vibrant swatches, an accent lifted to a minimum contrast against every wash stop, and text
/// and container colors that stay readable on top of it.
///
/// The role swatches are kept beside the chosen seed so the wash and the controls can follow
/// different artwork colors instead of deriving every role from one average. Each role is
/// optional because a source image can legitimately contain no swatch in a target's HSL range.
public struct PaletteScheme: Hashable, Sendable {
    /// Product-specific tokens the scheme is built on. Defaults describe a dark surface with
    /// Material-style neutral text roles and a cyan fallback accent for monochrome sources.
    public struct Configuration: Hashable, Sendable {
        /// The opaque surface the wash fades into and containers are mixed from.
        public var surface: RGBColor
        /// Accent used when the palette's control seed is too grey to be useful.
        public var fallbackAccent: RGBColor
        /// Primary text color; assumed to be readable on `surface`.
        public var onSurface: RGBColor
        /// Preferred secondary text color, used when it meets `minimumContrast` on every wash stop.
        public var onSurfaceVariant: RGBColor
        /// WCAG contrast ratio required for accent and text against each wash stop.
        public var minimumContrast: Double
        /// Control seeds with less chroma than this are replaced by `fallbackAccent`.
        public var minimumAccentChroma: Double

        public init(
            surface: RGBColor = RGBColor(red8: 17, green8: 16, blue8: 25),
            fallbackAccent: RGBColor = RGBColor(red8: 111, green8: 216, blue8: 232),
            onSurface: RGBColor = RGBColor(red8: 233, green8: 231, blue8: 241),
            onSurfaceVariant: RGBColor = RGBColor(red8: 196, green8: 190, blue8: 210),
            minimumContrast: Double = 4.5,
            minimumAccentChroma: Double = 0.04
        ) {
            self.surface = surface
            self.fallbackAccent = fallbackAccent
            self.onSurface = onSurface
            self.onSurfaceVariant = onSurfaceVariant
            self.minimumContrast = minimumContrast
            self.minimumAccentChroma = minimumAccentChroma
        }

        public static let `default` = Configuration()
    }

    /// The color the scheme is anchored on: the light-vibrant, light-muted, vibrant or dominant
    /// swatch, in that order of preference.
    public let seed: RGBColor
    public let darkMutedSeed: RGBColor?
    public let vibrantSeed: RGBColor?
    public let lightMutedSeed: RGBColor?
    public let lightVibrantSeed: RGBColor?
    public let configuration: Configuration

    public init(
        seed: RGBColor,
        darkMuted: RGBColor? = nil,
        vibrant: RGBColor? = nil,
        lightMuted: RGBColor? = nil,
        lightVibrant: RGBColor? = nil,
        configuration: Configuration = .default
    ) {
        self.seed = seed
        self.darkMutedSeed = darkMuted
        self.vibrantSeed = vibrant
        self.lightMutedSeed = lightMuted
        self.lightVibrantSeed = lightVibrant
        self.configuration = configuration
    }

    /// Builds a scheme from a generated palette. Returns `nil` when the palette has no swatches.
    public init?(palette: Palette, configuration: Configuration = .default) {
        guard let dominant = palette.dominant else { return nil }
        let seed = palette.lightVibrant?.color
            ?? palette.lightMuted?.color
            ?? palette.vibrant?.color
            ?? dominant.color
        self.init(
            seed: seed,
            darkMuted: palette.darkMuted?.color,
            vibrant: palette.vibrant?.color,
            lightMuted: palette.lightMuted?.color,
            lightVibrant: palette.lightVibrant?.color,
            configuration: configuration
        )
    }

    /// Generates a palette from `pixels` with the standard filter, retrying with
    /// ``Palette/Filter/lightnessOnly`` when the standard filter rejects every color, and builds a
    /// scheme from the result. Returns `nil` when neither pass yields a swatch.
    public init?(pixels: [UInt32], maxColors: Int = Palette.defaultColorCount, configuration: Configuration = .default) {
        let palette = Palette.generate(pixels: pixels, maxColors: maxColors, retryLightnessOnly: true)
        self.init(palette: palette, configuration: configuration)
    }

    /// A mid-grey scheme for use before extraction finishes or when it produces nothing.
    public static func neutral(configuration: Configuration = .default) -> PaletteScheme {
        PaletteScheme(seed: RGBColor(red: 0.25, green: 0.25, blue: 0.25), configuration: configuration)
    }

    public static let neutral = PaletteScheme.neutral()

    // MARK: Role swatches

    /// The dark variant used for the wash; falls back to the seed pulled most of the way to the surface.
    public var darkMuted: RGBColor { darkMutedSeed ?? seed.mixed(with: configuration.surface, fraction: 0.65) }
    public var vibrant: RGBColor { vibrantSeed ?? seed }
    public var lightMuted: RGBColor? { lightMutedSeed }
    public var lightVibrant: RGBColor? { lightVibrantSeed }

    // MARK: Derived roles

    /// The opaque surface from the configuration.
    public var surface: RGBColor { configuration.surface }

    /// Three opaque stops fading from a dark-muted tint to the plain surface, for a top-to-bottom wash.
    public var washStops: [RGBColor] {
        let surface = configuration.surface
        return [
            surface.mixed(with: darkMuted, fraction: 0.44),
            surface.mixed(with: darkMuted.mixed(with: vibrant, fraction: 0.35), fraction: 0.26),
            surface,
        ]
    }

    /// The control accent: the lightest colorful role swatch, pushed toward white (dark surfaces)
    /// or black (light surfaces) until it meets `minimumContrast` against every wash stop.
    public var accent: RGBColor {
        let controlSeed = lightVibrant ?? lightMuted ?? vibrant
        let base = controlSeed.chroma >= configuration.minimumAccentChroma ? controlSeed : configuration.fallbackAccent
        return base.readable(on: washStops, minimum: configuration.minimumContrast)
    }

    /// Black or white, whichever reads better on ``accent``.
    public var onAccent: RGBColor { accent.onColor }

    /// `onSurface` when it is readable on every wash stop, otherwise `onSurface` pushed toward
    /// white or black until it is.
    public var primaryText: RGBColor {
        configuration.onSurface.readable(on: washStops, minimum: configuration.minimumContrast)
    }

    /// `onSurfaceVariant` when it is readable on every wash stop, then `onSurface`, then
    /// `onSurface` pushed toward white or black until it is.
    public var secondaryText: RGBColor {
        let minimum = configuration.minimumContrast
        let stops = washStops
        if stops.allSatisfy({ configuration.onSurfaceVariant.contrast(with: $0) >= minimum }) {
            return configuration.onSurfaceVariant
        }
        return configuration.onSurface.readable(on: stops, minimum: minimum)
    }

    public var primaryContainer: RGBColor { configuration.surface.mixed(with: accent, fraction: 0.16) }
    public var secondaryContainer: RGBColor { configuration.surface.mixed(with: accent, fraction: 0.11) }
}
