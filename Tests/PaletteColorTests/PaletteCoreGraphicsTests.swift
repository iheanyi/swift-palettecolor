// PaletteColor
// SPDX-License-Identifier: Apache-2.0

#if canImport(CoreGraphics)
import CoreGraphics
import XCTest
import PaletteColor

final class PaletteCoreGraphicsTests: XCTestCase {
    private func makeImage(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    func testPixelExtractionUsesCanonicalSRGBRGBA() throws {
        let image = try makeImage(width: 2, height: 2, rgba: [
            0x20, 0x70, 0xD8, 0xFF,
            0xD0, 0x20, 0xC0, 0xFF,
            0x58, 0x88, 0x60, 0xFF,
            0xA0, 0xA0, 0xA0, 0xFF,
        ])
        XCTAssertEqual(Palette.pixels(from: image), [0x2070D8, 0xD020C0, 0x588860, 0xA0A0A0])
    }

    func testPixelExtractionUnpremultipliesTranslucentPixels() throws {
        // 50% alpha, premultiplied channels of 0x40/0x80/0xC0 decode back to roughly double.
        let image = try makeImage(width: 1, height: 1, rgba: [0x40, 0x80, 0x60, 0x80])
        let pixels = try XCTUnwrap(Palette.pixels(from: image))
        XCTAssertEqual(pixels.count, 1)
        let pixel = pixels[0]
        XCTAssertEqual(Int((pixel >> 16) & 0xff), 0x80, accuracy: 2)
        XCTAssertEqual(Int((pixel >> 8) & 0xff), 0xFF, accuracy: 2)
        XCTAssertEqual(Int(pixel & 0xff), 0xC0, accuracy: 2)
    }

    func testLargeImagesAreDownscaledByArea() throws {
        let width = 224, height = 224
        var rgba = [UInt8](repeating: 0xFF, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = 0x20; rgba[index + 1] = 0x70; rgba[index + 2] = 0xD8
        }
        let image = try makeImage(width: width, height: height, rgba: rgba)
        let pixels = try XCTUnwrap(Palette.pixels(from: image))
        XCTAssertEqual(pixels.count, 112 * 112)
        XCTAssertTrue(pixels.allSatisfy { $0 == 0x2070D8 })

        let palette = try XCTUnwrap(Palette.generate(image: image))
        XCTAssertEqual(palette.dominant?.rgb, 0x2070D8)
        XCTAssertEqual(palette.dominant?.population, 112 * 112)
    }

    func testGenerateFromImageRetriesWithLightnessOnlyFilter() throws {
        let image = try makeImage(width: 2, height: 2, rgba: Array(repeating: [0xD0, 0x60, 0x40, 0xFF], count: 4).flatMap { $0 })
        let standard = try XCTUnwrap(Palette.generate(image: image))
        XCTAssertTrue(standard.isEmpty)
        let retried = try XCTUnwrap(Palette.generate(image: image, retryLightnessOnly: true))
        XCTAssertEqual(retried.dominant?.rgb, 0xD06040)
        XCTAssertNotNil(retried.vibrant)
    }

    func testSchemeFromImage() throws {
        let image = try makeImage(width: 2, height: 2, rgba: [
            0x20, 0x70, 0xD8, 0xFF,
            0xD0, 0x20, 0xC0, 0xFF,
            0x58, 0x88, 0x60, 0xFF,
            0xA0, 0xA0, 0xA0, 0xFF,
        ])
        let scheme = try XCTUnwrap(PaletteScheme(image: image))
        XCTAssertEqual(scheme.seed.rgb, 0xA0A0A0)
        XCTAssertEqual(scheme.vibrant.rgb, 0x2070D8)
    }

    func testMediaArtworkSchemeFromImageMatchesPixelPath() throws {
        let width = 224, height = 224
        var rgba = [UInt8](repeating: 0xFF, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = 0x20; rgba[index + 1] = 0x70; rgba[index + 2] = 0xD8
        }
        let image = try makeImage(width: width, height: height, rgba: rgba)
        let pixels = try XCTUnwrap(MediaArtworkScheme.pixels(from: image))
        XCTAssertEqual(pixels.count, 112 * 112)
        XCTAssertTrue(pixels.allSatisfy { $0 == 0x2070D8 })

        let scheme = MediaArtworkScheme(image: image)
        XCTAssertEqual(scheme.seed.rgb, 0x2070D8)
        XCTAssertEqual(scheme, MediaArtworkScheme(pixels: pixels))
    }

    func testMediaArtworkSchemePixelsTruncateLikeWallpaperColors() throws {
        let width = 300, height = 200
        var rgba = [UInt8](repeating: 0xFF, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                if x < 210 {
                    rgba[index] = 0xA8; rgba[index + 1] = 0xE6; rgba[index + 2] = 0x3C
                } else {
                    rgba[index] = 0xE8; rgba[index + 1] = 0x5C; rgba[index + 2] = 0xA0
                }
            }
        }
        let image = try makeImage(width: width, height: height, rgba: rgba)
        let pixels = try XCTUnwrap(MediaArtworkScheme.pixels(from: image))
        // WallpaperColors truncates to 137×91; Palette.Builder would ceil to 138×92.
        XCTAssertEqual(pixels.count, 137 * 91)
        XCTAssertEqual(try XCTUnwrap(Palette.pixels(from: image)).count, 138 * 92)
        let scheme = MediaArtworkScheme(image: image)
        XCTAssertEqual(scheme.seedHCT.hue, 129, accuracy: 3)
    }

    func testCGColorConversion() {
        let color = RGBColor(rgb: 0x2070D8).cgColor
        let components = color.components ?? []
        XCTAssertEqual(components.count, 4)
        XCTAssertEqual(Double(components[0]), Double(0x20) / 255, accuracy: 1e-6)
        XCTAssertEqual(Double(components[3]), 1)
    }
}
#endif
