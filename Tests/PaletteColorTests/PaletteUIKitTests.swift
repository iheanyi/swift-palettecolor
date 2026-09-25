// PaletteColor
// SPDX-License-Identifier: Apache-2.0

#if canImport(UIKit) && !os(watchOS)
import UIKit
import Foundation
import Testing
import PaletteColor

struct PaletteUIKitTests {
    private let left: UInt32 = 0x2070D8
    private let right: UInt32 = 0xD020C0

    /// A 2×1 image: `left` on the left, `right` on the right.
    private func makeCGImage() throws -> CGImage {
        let rgba: [UInt8] = [0x20, 0x70, 0xD8, 0xFF, 0xD0, 0x20, 0xC0, 0xFF]
        let provider = try #require(CGDataProvider(data: Data(rgba) as CFData))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGImage(
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: space,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func assertPixels(
        _ actual: [UInt32]?, equal expected: [UInt32], sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let pixels = try #require(actual, sourceLocation: sourceLocation)
        #expect(pixels.count == expected.count, sourceLocation: sourceLocation)
        for (pixel, wanted) in zip(pixels, expected) {
            for shift in [16, 8, 0] {
                let channel = Int((pixel >> UInt32(shift)) & 0xff)
                let wantedChannel = Int((wanted >> UInt32(shift)) & 0xff)
                #expect(abs(channel - wantedChannel) <= 2, sourceLocation: sourceLocation)
            }
        }
    }

    @Test func upImageUsesBackingBitmapUnchanged() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: .up)
        try assertPixels(Palette.pixels(from: image), equal: [left, right])
    }

    @Test func downOrientationIsAppliedBeforeExtraction() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: .down)
        #expect(image.size == CGSize(width: 2, height: 1))
        // Raw cgImage ignores orientation; the normalized path rotates 180° so the order flips.
        try assertPixels(Palette.pixels(from: image.cgImage!), equal: [left, right])
        try assertPixels(Palette.pixels(from: image), equal: [right, left])
    }

    @Test func upMirroredOrientationFlipsHorizontally() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: .upMirrored)
        try assertPixels(Palette.pixels(from: image), equal: [right, left])
    }

    @Test func rotatedOrientationsProduceDisplayedDimensions() throws {
        for orientation in [UIImage.Orientation.left, .right, .leftMirrored, .rightMirrored] {
            let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: orientation)
            #expect(image.size == CGSize(width: 1, height: 2), "\(orientation.rawValue)")
            let normalized = try #require(image.paletteNormalizedCGImage())
            #expect(normalized.width == 1)
            #expect(normalized.height == 2)
            let pixels = try #require(Palette.pixels(from: image))
            #expect(pixels.count == 2)
            // Rotations differ in which end comes first, but both source colors must survive.
            let matchesLeft = pixels.map { isClose($0, to: left) }
            let matchesRight = pixels.map { isClose($0, to: right) }
            #expect(matchesLeft.contains(true) && matchesRight.contains(true), "\(orientation.rawValue)")
        }
    }

    private func isClose(_ pixel: UInt32, to wanted: UInt32) -> Bool {
        [16, 8, 0].allSatisfy { shift in
            abs(Int((pixel >> UInt32(shift)) & 0xff) - Int((wanted >> UInt32(shift)) & 0xff)) <= 2
        }
    }

    @Test func scaleIsRenderedAtNativePixelSize() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 2, orientation: .down)
        #expect(image.size == CGSize(width: 1, height: 0.5))
        let normalized = try #require(image.paletteNormalizedCGImage())
        #expect(normalized.width == 2)
        #expect(normalized.height == 1)
    }

    @Test func generateAndSchemeFromOrientedUIImage() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: .left)
        let palette = try #require(Palette.generate(image: image))
        #expect(Set(palette.swatches.map(\.rgb)) == [0x2070D8, 0xD020C0])
        let scheme = try #require(PaletteScheme(image: image))
        #expect(scheme.vibrant.rgb == 0x2070D8)
    }

    @Test func mediaArtworkSchemeFromOrientedUIImageMatchesCGImage() throws {
        let cgImage = try makeCGImage()
        let expected = MediaArtworkScheme(image: cgImage)
        for orientation in [UIImage.Orientation.up, .down, .left, .rightMirrored] {
            let image = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
            let pixels = try #require(MediaArtworkScheme.pixels(from: image))
            #expect(pixels.count == 2, "\(orientation.rawValue)")
            // Orientation reorders pixels but not their colors, so the same seed wins (the redraw
            // may shift channels by a step or two, hence the tolerance rather than equality).
            let scheme = MediaArtworkScheme(image: image)
            #expect(abs(scheme.seedHCT.hue - expected.seedHCT.hue) <= 2, "\(orientation.rawValue)")
            #expect(abs(scheme.seedHCT.tone - expected.seedHCT.tone) <= 2, "\(orientation.rawValue)")
            #expect(abs(HCT(scheme.accent).tone - 90) <= 0.5, "\(orientation.rawValue)")
        }
    }

    /// `UIColor.systemBlue` resolved the same way `MediaArtworkScheme.systemBlueSeed` does it.
    private func expectedSystemBlue(_ traits: UITraitCollection?) -> RGBColor {
        let color = traits.map { UIColor.systemBlue.resolvedColor(with: $0) } ?? UIColor.systemBlue
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return RGBColor(red: Double(red), green: Double(green), blue: Double(blue))
    }

    @Test func systemBlueSeedResolvesUIColorSystemBlue() {
        // Apple's exact systemBlue components vary by OS release and appearance, so compare with
        // the live color rather than pinned hex values.
        let traitVariants = [
            nil, UITraitCollection(userInterfaceStyle: .light), UITraitCollection(userInterfaceStyle: .dark),
        ]
        for traits in traitVariants {
            let seed = MediaArtworkScheme.systemBlueSeed(compatibleWith: traits)
            let expected = expectedSystemBlue(traits)
            #expect(abs(seed.red - expected.red) <= 1e-6)
            #expect(abs(seed.green - expected.green) <= 1e-6)
            #expect(abs(seed.blue - expected.blue) <= 1e-6)

            // It is a system blue: dominant blue channel, low red, within Apple's historical range.
            #expect(seed.blue > 0.9)
            #expect(seed.red < 0.15)
            #expect(seed.green > 0.35)
            #expect(seed.green < 0.7)
            #expect(seed.rgb != 0x1B6EF3)   // never Google Blue
            #expect(seed.rgb != 0x6FD8E8)   // never the brand cyan
        }
        // The static Linux/default seed stays the documented iOS light approximation.
        #expect(MediaArtworkScheme.fallbackSeed.rgb == 0x007AFF)
    }

    @Test func unreadableUIImageFallsBackToSystemBlueNotMissingArtwork() {
        // An empty UIImage has no CGImage and no drawable size, so pixels cannot be read.
        let scheme = MediaArtworkScheme(image: UIImage())
        #expect(scheme.seed == MediaArtworkScheme.systemBlueSeed())
        #expect(scheme.seed.rgb != 0x1B6EF3)
        #expect(scheme != .missingArtwork)

        let pinned = MediaArtworkScheme(image: UIImage(), fallbackSeed: MediaArtworkScheme.fallbackSeed)
        #expect(pinned == .unreadableArtwork)
        #expect(pinned.seed.rgb == 0x007AFF)
    }

    @Test func uIColorConversion() {
        let color = UIColor(RGBColor(rgb: 0x2070D8))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(abs(Double(red) - (Double(0x20) / 255)) <= 1e-6)
        #expect(abs(Double(blue) - (Double(0xD8) / 255)) <= 1e-6)
        #expect(alpha == 1)
    }
}
#endif
