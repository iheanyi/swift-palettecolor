// PaletteColor
// SPDX-License-Identifier: Apache-2.0

#if canImport(UIKit) && !os(watchOS)
import UIKit
import XCTest
import PaletteColor

final class PaletteUIKitTests: XCTestCase {
    private let left: UInt32 = 0x2070D8
    private let right: UInt32 = 0xD020C0

    /// A 2×1 image: `left` on the left, `right` on the right.
    private func makeCGImage() throws -> CGImage {
        let rgba: [UInt8] = [0x20, 0x70, 0xD8, 0xFF, 0xD0, 0x20, 0xC0, 0xFF]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        return try XCTUnwrap(CGImage(
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func assertPixels(_ actual: [UInt32]?, equal expected: [UInt32], file: StaticString = #filePath, line: UInt = #line) throws {
        let pixels = try XCTUnwrap(actual, file: file, line: line)
        XCTAssertEqual(pixels.count, expected.count, file: file, line: line)
        for (pixel, wanted) in zip(pixels, expected) {
            for shift in [16, 8, 0] {
                XCTAssertEqual(Int((pixel >> UInt32(shift)) & 0xff), Int((wanted >> UInt32(shift)) & 0xff), accuracy: 2, file: file, line: line)
            }
        }
    }

    func testUpImageUsesBackingBitmapUnchanged() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: .up)
        try assertPixels(Palette.pixels(from: image), equal: [left, right])
    }

    func testDownOrientationIsAppliedBeforeExtraction() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: .down)
        XCTAssertEqual(image.size, CGSize(width: 2, height: 1))
        // Raw cgImage ignores orientation; the normalized path rotates 180° so the order flips.
        try assertPixels(Palette.pixels(from: image.cgImage!), equal: [left, right])
        try assertPixels(Palette.pixels(from: image), equal: [right, left])
    }

    func testUpMirroredOrientationFlipsHorizontally() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: .upMirrored)
        try assertPixels(Palette.pixels(from: image), equal: [right, left])
    }

    func testRotatedOrientationsProduceDisplayedDimensions() throws {
        for orientation in [UIImage.Orientation.left, .right, .leftMirrored, .rightMirrored] {
            let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: orientation)
            XCTAssertEqual(image.size, CGSize(width: 1, height: 2), "\(orientation.rawValue)")
            let normalized = try XCTUnwrap(image.paletteNormalizedCGImage())
            XCTAssertEqual(normalized.width, 1)
            XCTAssertEqual(normalized.height, 2)
            let pixels = try XCTUnwrap(Palette.pixels(from: image))
            XCTAssertEqual(pixels.count, 2)
            // Rotations differ in which end comes first, but both source colors must survive.
            let matchesLeft = pixels.map { isClose($0, to: left) }
            let matchesRight = pixels.map { isClose($0, to: right) }
            XCTAssertTrue(matchesLeft.contains(true) && matchesRight.contains(true), "\(orientation.rawValue)")
        }
    }

    private func isClose(_ pixel: UInt32, to wanted: UInt32) -> Bool {
        [16, 8, 0].allSatisfy { shift in
            abs(Int((pixel >> UInt32(shift)) & 0xff) - Int((wanted >> UInt32(shift)) & 0xff)) <= 2
        }
    }

    func testScaleIsRenderedAtNativePixelSize() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 2, orientation: .down)
        XCTAssertEqual(image.size, CGSize(width: 1, height: 0.5))
        let normalized = try XCTUnwrap(image.paletteNormalizedCGImage())
        XCTAssertEqual(normalized.width, 2)
        XCTAssertEqual(normalized.height, 1)
    }

    func testGenerateAndSchemeFromOrientedUIImage() throws {
        let image = UIImage(cgImage: try makeCGImage(), scale: 1, orientation: .left)
        let palette = try XCTUnwrap(Palette.generate(image: image))
        XCTAssertEqual(Set(palette.swatches.map(\.rgb)), [0x2070D8, 0xD020C0])
        let scheme = try XCTUnwrap(PaletteScheme(image: image))
        XCTAssertEqual(scheme.vibrant.rgb, 0x2070D8)
    }

    func testMediaArtworkSchemeFromOrientedUIImageMatchesCGImage() throws {
        let cgImage = try makeCGImage()
        let expected = MediaArtworkScheme(image: cgImage)
        for orientation in [UIImage.Orientation.up, .down, .left, .rightMirrored] {
            let image = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
            let pixels = try XCTUnwrap(MediaArtworkScheme.pixels(from: image))
            XCTAssertEqual(pixels.count, 2, "\(orientation.rawValue)")
            // Orientation reorders pixels but not their colors, so the same seed wins (the redraw
            // may shift channels by a step or two, hence the tolerance rather than equality).
            let scheme = MediaArtworkScheme(image: image)
            XCTAssertEqual(scheme.seedHCT.hue, expected.seedHCT.hue, accuracy: 2, "\(orientation.rawValue)")
            XCTAssertEqual(scheme.seedHCT.tone, expected.seedHCT.tone, accuracy: 2, "\(orientation.rawValue)")
            XCTAssertEqual(HCT(scheme.accent).tone, 90, accuracy: 0.5, "\(orientation.rawValue)")
        }
    }

    func testUnreadableUIImageFallsBackToGoogleBlueNotMissingArtwork() {
        // An empty UIImage has no CGImage and no drawable size, so pixels cannot be read.
        let scheme = MediaArtworkScheme(image: UIImage())
        XCTAssertEqual(scheme, .unreadableArtwork)
        XCTAssertEqual(scheme.seed.rgb, 0x1B6EF3)
        XCTAssertNotEqual(scheme, .missingArtwork)
    }

    func testUIColorConversion() {
        let color = UIColor(RGBColor(rgb: 0x2070D8))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(Double(red), Double(0x20) / 255, accuracy: 1e-6)
        XCTAssertEqual(Double(blue), Double(0xD8) / 255, accuracy: 1e-6)
        XCTAssertEqual(alpha, 1)
    }
}
#endif
