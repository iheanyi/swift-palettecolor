// PaletteColor
// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 the swift-palettecolor authors. Licensed under the Apache License, Version 2.0.

#if canImport(UIKit)
import UIKit

extension UIImage {
    /// A `CGImage` whose pixel data is laid out the way the image is displayed.
    ///
    /// `UIImage.cgImage` returns the decoder's untransformed bitmap and ignores
    /// `imageOrientation`, so a photo shot in portrait comes back sideways. Images that are
    /// already `.up` and CGImage-backed are returned directly; anything else (rotated/mirrored
    /// EXIF orientations, CIImage-backed images) is redrawn at its native pixel size with
    /// `UIGraphicsImageRenderer`, which applies the orientation. Redrawing is unavailable on
    /// watchOS, where the raw `cgImage` is returned instead.
    ///
    /// Palette extraction itself is orientation-agnostic (it only counts colors), but the
    /// downscale in ``Palette/pixels(from:resizeArea:)`` samples the bitmap by position, so
    /// normalizing first keeps results identical to what the user sees.
    public func paletteNormalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        #if os(watchOS)
        return cgImage
        #else
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }.cgImage
        #endif
    }
}

extension Palette {
    /// Converts a `UIImage` to opaque RGB888 pixels, honouring `imageOrientation`. The
    /// orientation-corrected bitmap is then downscaled exactly like the `CGImage` overload.
    public static func pixels(from image: UIImage, resizeArea: Int = defaultResizeArea) -> [UInt32]? {
        guard let cgImage = image.paletteNormalizedCGImage() else { return nil }
        return pixels(from: cgImage, resizeArea: resizeArea)
    }

    /// Generates a palette from an orientation-corrected rendering of `image`. Returns `nil` when
    /// the image has no drawable content or pixels cannot be read. See
    /// ``Palette/generate(image:maxColors:filter:retryLightnessOnly:resizeArea:)`` for the
    /// lightness-only retry.
    public static func generate(
        image: UIImage,
        maxColors: Int = defaultColorCount,
        filter: Filter = .standard,
        retryLightnessOnly: Bool = false,
        resizeArea: Int = defaultResizeArea
    ) -> Palette? {
        guard let cgImage = image.paletteNormalizedCGImage() else { return nil }
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
    /// Extracts a palette from an orientation-corrected rendering of `image` and builds a scheme.
    /// Returns `nil` when the image has no drawable content or yields no swatches.
    public init?(image: UIImage, maxColors: Int = Palette.defaultColorCount, configuration: Configuration = .default) {
        guard let cgImage = image.paletteNormalizedCGImage() else { return nil }
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
