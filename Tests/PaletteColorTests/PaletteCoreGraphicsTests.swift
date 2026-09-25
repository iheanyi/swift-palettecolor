// PaletteColor
// SPDX-License-Identifier: Apache-2.0

#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import Testing
import PaletteColor

struct PaletteCoreGraphicsTests {
    private func makeImage(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(rgba) as CFData))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
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

    @Test func pixelExtractionUsesCanonicalSRGBRGBA() throws {
        let image = try makeImage(width: 2, height: 2, rgba: [
            0x20, 0x70, 0xD8, 0xFF,
            0xD0, 0x20, 0xC0, 0xFF,
            0x58, 0x88, 0x60, 0xFF,
            0xA0, 0xA0, 0xA0, 0xFF,
        ])
        #expect(Palette.pixels(from: image) == [0x2070D8, 0xD020C0, 0x588860, 0xA0A0A0])
    }

    @Test func pixelExtractionUnpremultipliesTranslucentPixels() throws {
        // 50% alpha, premultiplied channels of 0x40/0x80/0xC0 decode back to roughly double.
        let image = try makeImage(width: 1, height: 1, rgba: [0x40, 0x80, 0x60, 0x80])
        let pixels = try #require(Palette.pixels(from: image))
        #expect(pixels.count == 1)
        let pixel = pixels[0]
        #expect(abs(Int((pixel >> 16) & 0xff) - 0x80) <= 2)
        #expect(abs(Int((pixel >> 8) & 0xff) - 0xFF) <= 2)
        #expect(abs(Int(pixel & 0xff) - 0xC0) <= 2)
    }

    @Test func largeImagesAreDownscaledByArea() throws {
        let width = 224, height = 224
        var rgba = [UInt8](repeating: 0xFF, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = 0x20; rgba[index + 1] = 0x70; rgba[index + 2] = 0xD8
        }
        let image = try makeImage(width: width, height: height, rgba: rgba)
        let pixels = try #require(Palette.pixels(from: image))
        #expect(pixels.count == (112 * 112))
        #expect(pixels.allSatisfy { $0 == 0x2070D8 })

        let palette = try #require(Palette.generate(image: image))
        #expect(palette.dominant?.rgb == 0x2070D8)
        #expect(palette.dominant?.population == (112 * 112))
    }

    @Test func generateFromImageRetriesWithLightnessOnlyFilter() throws {
        let rgba: [UInt8] = Array(repeating: [0xD0, 0x60, 0x40, 0xFF], count: 4).flatMap { $0 }
        let image = try makeImage(width: 2, height: 2, rgba: rgba)
        let standard = try #require(Palette.generate(image: image))
        #expect(standard.isEmpty)
        let retried = try #require(Palette.generate(image: image, retryLightnessOnly: true))
        #expect(retried.dominant?.rgb == 0xD06040)
        #expect(retried.vibrant != nil)
    }

    @Test func schemeFromImage() throws {
        let image = try makeImage(width: 2, height: 2, rgba: [
            0x20, 0x70, 0xD8, 0xFF,
            0xD0, 0x20, 0xC0, 0xFF,
            0x58, 0x88, 0x60, 0xFF,
            0xA0, 0xA0, 0xA0, 0xFF,
        ])
        let scheme = try #require(PaletteScheme(image: image))
        #expect(scheme.seed.rgb == 0xA0A0A0)
        #expect(scheme.vibrant.rgb == 0x2070D8)
    }

    @Test func mediaArtworkSchemeFromImageMatchesPixelPath() throws {
        let width = 224, height = 224
        var rgba = [UInt8](repeating: 0xFF, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = 0x20; rgba[index + 1] = 0x70; rgba[index + 2] = 0xD8
        }
        let image = try makeImage(width: width, height: height, rgba: rgba)
        let pixels = try #require(MediaArtworkScheme.pixels(from: image))
        #expect(pixels.count == (112 * 112))
        #expect(pixels.allSatisfy { $0 == 0x2070D8 })

        let scheme = MediaArtworkScheme(image: image)
        #expect(scheme.seed.rgb == 0x2070D8)
        #expect(scheme == MediaArtworkScheme(pixels: pixels))
    }

    @Test func mediaArtworkSchemePixelsTruncateLikeWallpaperColors() throws {
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
        let pixels = try #require(MediaArtworkScheme.pixels(from: image))
        // WallpaperColors truncates to 137×91; Palette.Builder would ceil to 138×92.
        #expect(pixels.count == (137 * 91))
        let extracted = try #require(Palette.pixels(from: image))
        #expect(extracted.count == 138 * 92)
        let scheme = MediaArtworkScheme(image: image)
        #expect(abs(scheme.seedHCT.hue - 129) <= 3)
    }

    @Test func cGColorConversion() {
        let color = RGBColor(rgb: 0x2070D8).cgColor
        let components = color.components ?? []
        #expect(components.count == 4)
        #expect(abs(Double(components[0]) - (Double(0x20) / 255)) <= 1e-6)
        #expect(Double(components[3]) == 1)
    }
}
#endif
