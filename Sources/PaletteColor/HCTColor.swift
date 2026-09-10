// PaletteColor
// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 the swift-palettecolor authors. Licensed under the Apache License, Version 2.0.

import Foundation

/// A color in Material's HCT space: CAM16 hue and chroma with L* tone.
///
/// This is a value-type facade over the vendored Material Color Utilities `Hct` solver, so the
/// numbers here match what Android's `com.google.ux.material.libmonet` and SystemUI compute for
/// the same sRGB value. ``init(_:)`` measures an existing color; ``color`` solves the requested
/// hue/chroma/tone back to sRGB, reducing chroma until the color fits the sRGB gamut.
public struct HCT: Hashable, Sendable {
    /// CAM16 hue in degrees, `0..<360`.
    public var hue: Double
    /// CAM16 chroma. Informally colorfulness; the achievable maximum depends on hue and tone.
    public var chroma: Double
    /// L* lightness, `0...100`.
    public var tone: Double

    public init(hue: Double, chroma: Double, tone: Double) {
        self.hue = hue
        self.chroma = chroma
        self.tone = tone
    }

    /// Measures `color` in default (sRGB) viewing conditions.
    public init(_ color: RGBColor) {
        self.init(rgb: color.rgb)
    }

    /// Measures an RGB888 value packed as `0xRRGGBB`.
    public init(rgb: UInt32) {
        let hct = Hct.fromInt(MediaArtworkScheme.argb(fromRGB: rgb))
        self.init(hue: hct.hue, chroma: hct.chroma, tone: hct.tone)
    }

    /// The sRGB color with this hue and tone and the highest chroma up to ``chroma`` that the
    /// gamut allows. Equivalent to `Hct.from(hue, chroma, tone).toInt()` in Material Color Utilities.
    public var color: RGBColor {
        RGBColor(rgb: MediaArtworkScheme.rgb(fromARGB: Hct.from(hue, chroma, tone).toInt()))
    }
}
