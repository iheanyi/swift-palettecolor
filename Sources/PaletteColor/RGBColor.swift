// PaletteColor
// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 the swift-palettecolor authors. Licensed under the Apache License, Version 2.0.

import Foundation

/// An opaque sRGB color with `Double` channels in `0...1`, plus the WCAG contrast helpers
/// used to keep palette-derived accents and text readable against palette-derived surfaces.
public struct RGBColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Creates a color from 8-bit channels.
    public init(red8: Int, green8: Int, blue8: Int) {
        self.init(red: Double(red8) / 255, green: Double(green8) / 255, blue: Double(blue8) / 255)
    }

    /// Creates a color from an RGB888 value packed as `0xRRGGBB`. Any bits above the low 24 are ignored.
    public init(rgb: UInt32) {
        self.init(
            red8: Int((rgb >> 16) & 0xff),
            green8: Int((rgb >> 8) & 0xff),
            blue8: Int(rgb & 0xff)
        )
    }

    public static let white = RGBColor(red: 1, green: 1, blue: 1)
    public static let black = RGBColor(red: 0, green: 0, blue: 0)

    /// RGB888 packed as `0xRRGGBB`, rounding each channel to the nearest 8-bit value.
    public var rgb: UInt32 {
        func channel(_ value: Double) -> UInt32 {
            UInt32(min(255, max(0, (value * 255).rounded())))
        }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }

    /// The spread between the largest and smallest channel. Values near zero are grey.
    public var chroma: Double { max(red, green, blue) - min(red, green, blue) }

    /// Linearly interpolates toward `other` in sRGB space. `fraction` is clamped to `0...1`.
    public func mixed(with other: RGBColor, fraction: Double) -> RGBColor {
        let t = min(1, max(0, fraction))
        return RGBColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    /// WCAG 2.x relative luminance.
    public var luminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return linear(red) * 0.2126 + linear(green) * 0.7152 + linear(blue) * 0.0722
    }

    /// WCAG 2.x contrast ratio in `1...21`.
    public func contrast(with other: RGBColor) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }

    /// Moves this color toward white or black until it reaches `minimum` contrast against every
    /// background.
    ///
    /// The color is returned unchanged when it already meets the minimum against each background.
    /// Otherwise the lift direction is whichever neutral (white or black) contrasts best with the
    /// backgrounds as a whole, so dark washes lift accents toward white and light surfaces pull
    /// them toward black. A binary search then finds the smallest mix in that direction that
    /// satisfies every background. If the preferred neutral cannot reach the minimum against all
    /// backgrounds the other direction is tried; if neither can, the better neutral is returned.
    public func readable(on backgrounds: [RGBColor], minimum: Double = 4.5) -> RGBColor {
        guard !backgrounds.isEmpty else { return self }
        func satisfies(_ candidate: RGBColor) -> Bool {
            backgrounds.allSatisfy { candidate.contrast(with: $0) >= minimum }
        }
        func worstContrast(_ candidate: RGBColor) -> Double {
            backgrounds.map { candidate.contrast(with: $0) }.min() ?? 0
        }
        if satisfies(self) { return self }

        let whiteContrast = worstContrast(.white)
        let blackContrast = worstContrast(.black)
        let directions: [RGBColor] = whiteContrast >= blackContrast ? [.white, .black] : [.black, .white]
        for target in directions where satisfies(target) {
            var low = 0.0, high = 1.0
            for _ in 0..<20 {
                let middle = (low + high) / 2
                if satisfies(mixed(with: target, fraction: middle)) {
                    high = middle
                } else {
                    low = middle
                }
            }
            return mixed(with: target, fraction: high)
        }
        return directions[0]
    }

    /// Black or white, whichever has the higher contrast against this color.
    public var onColor: RGBColor {
        RGBColor.black.contrast(with: self) >= RGBColor.white.contrast(with: self) ? .black : .white
    }
}
