// PaletteColor
// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 the swift-palettecolor authors. Licensed under the Apache License, Version 2.0.

#if canImport(UIKit)
import UIKit

extension Palette {
    /// Generates a palette from the image's backing `CGImage`. Returns `nil` when the image has no
    /// `CGImage` (for example, CIImage-backed images) or pixels cannot be read. See
    /// ``Palette/generate(image:maxColors:filter:retryLightnessOnly:resizeArea:)`` for the
    /// lightness-only retry.
    public static func generate(
        image: UIImage,
        maxColors: Int = defaultColorCount,
        filter: Filter = .standard,
        retryLightnessOnly: Bool = false,
        resizeArea: Int = defaultResizeArea
    ) -> Palette? {
        guard let cgImage = image.cgImage else { return nil }
        return generate(
            image: cgImage,
            maxColors: maxColors,
            filter: filter,
            retryLightnessOnly: retryLightnessOnly,
            resizeArea: resizeArea
        )
    }
}

extension PaletteScheme {
    /// Extracts a palette from `image` and builds a scheme. Returns `nil` when the image has no
    /// `CGImage` or yields no swatches.
    public init?(image: UIImage, maxColors: Int = Palette.defaultColorCount, configuration: Configuration = .default) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(image: cgImage, maxColors: maxColors, configuration: configuration)
    }
}

extension UIColor {
    public convenience init(_ color: RGBColor) {
        self.init(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }
}

extension RGBColor {
    public var uiColor: UIColor { UIColor(self) }
}
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

extension Palette {
    /// Generates a palette from the image's best `CGImage` representation.
    public static func generate(
        image: NSImage,
        maxColors: Int = defaultColorCount,
        filter: Filter = .standard,
        retryLightnessOnly: Bool = false,
        resizeArea: Int = defaultResizeArea
    ) -> Palette? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return generate(
            image: cgImage,
            maxColors: maxColors,
            filter: filter,
            retryLightnessOnly: retryLightnessOnly,
            resizeArea: resizeArea
        )
    }
}

extension PaletteScheme {
    public init?(image: NSImage, maxColors: Int = Palette.defaultColorCount, configuration: Configuration = .default) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.init(image: cgImage, maxColors: maxColors, configuration: configuration)
    }
}

extension NSColor {
    public convenience init(_ color: RGBColor) {
        self.init(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }
}

extension RGBColor {
    public var nsColor: NSColor { NSColor(self) }
}
#endif

#if canImport(SwiftUI)
import SwiftUI

extension Color {
    public init(_ color: RGBColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
    }
}

extension RGBColor {
    public var color: Color { Color(self) }
}

extension Palette.Swatch {
    /// The swatch as a SwiftUI `Color`.
    public var swiftUIColor: Color { Color(color) }
}
#endif
