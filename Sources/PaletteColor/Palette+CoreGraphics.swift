// PaletteColor
// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 the swift-palettecolor authors. Licensed under the Apache License, Version 2.0.

#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

extension Palette {
    /// Converts a `CGImage` to Android-like opaque RGB888 pixels.
    ///
    /// The Android builder scales by area to `112 * 112` and uses
    /// `Bitmap.createScaledBitmap(..., filter = false)`, so the context here uses sRGB, explicit
    /// unpremultiplication, and nearest-neighbour interpolation as well. Returns `nil` when the
    /// image is empty or a bitmap context cannot be created.
    public static func pixels(from image: CGImage, resizeArea: Int = defaultResizeArea) -> [UInt32]? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let sourceArea = sourceWidth * sourceHeight
        let scale = sourceArea > resizeArea
            ? sqrt(Double(resizeArea) / Double(sourceArea))
            : 1
        return CGImagePixels.render(
            image,
            width: max(1, Int(ceil(Double(sourceWidth) * scale))),
            height: max(1, Int(ceil(Double(sourceHeight) * scale)))
        )
    }
}

enum CGImagePixels {
    /// Draws `image` into a `width` × `height` sRGB bitmap with nearest-neighbour sampling and
    /// returns opaque RGB888 pixels. Returns `nil` when a bitmap context cannot be created.
    static func render(_ image: CGImage, width: Int, height: Int) -> [UInt32]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        // Core Graphics does not support a packed non-premultiplied RGBA context on every
        // runtime. Premultiplied-last is supported; unpremultiply below so translucent source
        // pixels retain their decoded RGB channels before the alpha-free quantizer sees them.
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let rendered = bytes.withUnsafeMutableBytes { rawBuffer -> CGContext? in
            guard let baseAddress = rawBuffer.baseAddress, let colorSpace else { return nil }
            let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
            context?.interpolationQuality = .none
            context?.setShouldAntialias(false)
            context?.setBlendMode(.copy)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context
        }
        guard rendered != nil else { return nil }
        return stride(from: 0, to: bytes.count, by: 4).map { index in
            let alpha = Int(bytes[index + 3])
            func unpremultiplied(_ component: UInt8) -> UInt32 {
                guard alpha > 0 else { return 0 }
                return UInt32(min(255, (Int(component) * 255 + alpha / 2) / alpha))
            }
            return unpremultiplied(bytes[index]) << 16
                | unpremultiplied(bytes[index + 1]) << 8
                | unpremultiplied(bytes[index + 2])
        }
    }
}

extension Palette {
    /// Downscales `image` like the Android builder and generates a palette from it.
    /// Returns `nil` when pixels cannot be read from the image.
    ///
    /// Pass `retryLightnessOnly: true` to rerun with ``Filter/lightnessOnly`` when `filter`
    /// rejects every color, the same second pass ``PaletteScheme`` always performs.
    public static func generate(
        image: CGImage,
        maxColors: Int = defaultColorCount,
        filter: Filter = .standard,
        retryLightnessOnly: Bool = false,
        resizeArea: Int = defaultResizeArea
    ) -> Palette? {
        guard let pixels = pixels(from: image, resizeArea: resizeArea) else { return nil }
        return generate(pixels: pixels, maxColors: maxColors, filter: filter, retryLightnessOnly: retryLightnessOnly)
    }
}

extension PaletteScheme {
    /// Extracts a palette from `image` (standard filter, retrying with the lightness-only filter)
    /// and builds a scheme from it. Returns `nil` when the image yields no swatches.
    public init?(image: CGImage, maxColors: Int = Palette.defaultColorCount, configuration: Configuration = .default) {
        guard let pixels = Palette.pixels(from: image) else { return nil }
        self.init(pixels: pixels, maxColors: maxColors, configuration: configuration)
    }
}

extension MediaArtworkScheme {
    /// Converts a `CGImage` to opaque RGB888 pixels, downscaling like `WallpaperColors.fromBitmap`
    /// (nearest neighbour to at most `maxArea` pixels, dimensions truncated, minimum 1). Images at
    /// or under the limit are read at native size. Returns `nil` when the image is empty or a
    /// bitmap context cannot be created.
    public static func pixels(from image: CGImage, maxArea: Int = maxBitmapArea) -> [UInt32]? {
        guard image.width > 0, image.height > 0 else { return nil }
        let size = scaledSize(width: image.width, height: image.height, maxArea: maxArea)
            ?? (image.width, image.height)
        return CGImagePixels.render(image, width: size.width, height: size.height)
    }

    /// Downscales `image` like `WallpaperColors.fromBitmap`, quantizes it and builds the scheme.
    /// Returns `nil` when pixels cannot be read from the image.
    public init?(image: CGImage, maxArea: Int = maxBitmapArea) {
        guard let pixels = Self.pixels(from: image, maxArea: maxArea) else { return nil }
        self.init(pixels: pixels)
    }
}

extension RGBColor {
    public var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [CGFloat(red), CGFloat(green), CGFloat(blue), 1]
        )!
    }
}
#endif
