// PaletteColor
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PaletteColor

final class PaletteTests: XCTestCase {
    func testMatchesAndroidXDefaultPixelVectorAndTargetRoles() {
        // RGB888 fixture (alpha is deliberately absent, as AndroidX Swatch stores RGB only). The
        // quantized 5-bit colors and populations are the expected AndroidX values.
        let pixels: [UInt32] = [
            0x2070D8, 0x2070D8, 0x2070D8,
            0xD020C0, 0xD020C0,
            0x5C8A60, 0x5C8A60, 0x5C8A60, 0x5C8A60,
            0xA0A0A0, 0xA0A0A0, 0xA0A0A0,
            0x101010,
            0xF0F0F0,
            0x000000,
        ]

        let result = Palette.generate(pixels: pixels)

        XCTAssertEqual(result.swatches.map(\.rgb), [
            0x101010, 0x2070D8, 0x588860, 0xA0A0A0, 0xD020C0, 0xF0F0F0,
        ])
        XCTAssertEqual(result.swatches.map(\.population), [1, 3, 4, 3, 2, 1])
        XCTAssertEqual(result.dominant?.rgb, 0x588860)
        XCTAssertEqual(result.vibrant?.rgb, 0x2070D8)
        XCTAssertEqual(result.lightMuted?.rgb, 0xA0A0A0)
        XCTAssertEqual(result.muted?.rgb, 0x588860)
        XCTAssertEqual(result.darkMuted?.rgb, 0x101010)
        XCTAssertNil(result.lightVibrant)
        XCTAssertNil(result.darkVibrant)
        XCTAssertEqual(result[.vibrant], result.vibrant)
    }

    func testUsesLightnessOnlyFallbackOnlyWhenDefaultFilterRejectsEverything() {
        let pixels = Array(repeating: UInt32(0xFFFFFF), count: 12)
        XCTAssertTrue(Palette.generate(pixels: pixels).isEmpty)
        XCTAssertTrue(Palette.generate(pixels: pixels, filter: .lightnessOnly).isEmpty)

        let nearRed = Array(repeating: UInt32(0xD06040), count: 12)
        XCTAssertTrue(Palette.generate(pixels: nearRed).isEmpty)
        XCTAssertEqual(Palette.generate(pixels: nearRed, filter: .lightnessOnly).swatches.count, 1)
        XCTAssertEqual(Palette.generate(pixels: nearRed, retryLightnessOnly: true).swatches.count, 1)
        // The retry is a no-op when the caller already asked for the lightness-only filter.
        XCTAssertEqual(
            Palette.generate(pixels: nearRed, filter: .lightnessOnly, retryLightnessOnly: true),
            Palette.generate(pixels: nearRed, filter: .lightnessOnly)
        )
    }

    func testRetryIsNotUsedWhenStandardFilterSucceeds() {
        let mixed: [UInt32] = Array(repeating: 0x2070D8, count: 4) + Array(repeating: 0xD06040, count: 12)
        let standard = Palette.generate(pixels: mixed)
        let withRetry = Palette.generate(pixels: mixed, retryLightnessOnly: true)
        XCTAssertEqual(standard, withRetry)
        XCTAssertEqual(standard.swatches.map(\.rgb), [0x2070D8])
    }

    func testRetryYieldsRolesForRedILineArtwork() {
        let nearRed = Array(repeating: UInt32(0xD06040), count: 12)
        let palette = Palette.generate(pixels: nearRed, retryLightnessOnly: true)
        XCTAssertEqual(palette.dominant?.rgb, 0xD06040)
        XCTAssertNotNil(palette.vibrant)
    }

    func testEmptyInputProducesEmptyPalette() {
        let result = Palette.generate(pixels: [])
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(result.dominant)
        XCTAssertTrue(result.selected.isEmpty)
        XCTAssertEqual(result, .empty)
    }

    func testMedianCutReducesManyDistinctColorsToMaxColors() {
        // 4096 distinct quantized colors across the RGB cube (skipping the extreme black/white
        // corners the default filter would reject) force the median-cut path.
        var pixels: [UInt32] = []
        for r in stride(from: 8, through: 248, by: 16) {
            for g in stride(from: 8, through: 248, by: 16) {
                for b in stride(from: 8, through: 248, by: 16) {
                    pixels.append(UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b))
                }
            }
        }
        let result = Palette.generate(pixels: pixels, maxColors: 16)
        XCTAssertFalse(result.isEmpty)
        XCTAssertLessThanOrEqual(result.swatches.count, 16)
        XCTAssertGreaterThan(result.swatches.count, 1)
        XCTAssertLessThanOrEqual(result.swatches.reduce(0) { $0 + $1.population }, pixels.count)
        // Every swatch is a 5-bit approximation.
        for swatch in result.swatches {
            XCTAssertEqual(swatch.red & 0x7, 0)
            XCTAssertEqual(swatch.green & 0x7, 0)
            XCTAssertEqual(swatch.blue & 0x7, 0)
        }
        // Population ordering picks the dominant swatch.
        XCTAssertEqual(result.dominant, result.swatches.max { $0.population < $1.population })
    }

    func testSelectedSwatchesAreNotReusedAcrossTargets() {
        let pixels: [UInt32] = Array(repeating: 0x2070D8, count: 10) + Array(repeating: 0x588860, count: 5)
        let result = Palette.generate(pixels: pixels)
        let chosen = result.selected.values.map(\.rgb)
        XCTAssertEqual(Set(chosen).count, chosen.count)
    }

    func testHSLMatchesColorUtilsRGBToHSL() {
        let grey = HSL(rgb: 0xA0A0A0)
        XCTAssertEqual(grey.hue, 0)
        XCTAssertEqual(grey.saturation, 0)
        XCTAssertEqual(grey.lightness, Float(0xA0) / 255, accuracy: 1e-6)

        let red = HSL(red: 255, green: 0, blue: 0)
        XCTAssertEqual(red.hue, 0)
        XCTAssertEqual(red.saturation, 1)
        XCTAssertEqual(red.lightness, 0.5)

        let blue = HSL(rgb: 0x0000FF)
        XCTAssertEqual(blue.hue, 240)

        let magentaish = HSL(rgb: 0xD020C0)
        XCTAssertGreaterThan(magentaish.hue, 300)
        XCTAssertLessThan(magentaish.hue, 320)
    }

    func testStandardFilterRejectsRedILineButLightnessOnlyKeepsIt() {
        let nearRed: UInt32 = 0xD06040
        let hsl = HSL(rgb: nearRed)
        XCTAssertTrue(hsl.hue >= 10 && hsl.hue <= 37)
        XCTAssertFalse(Palette.Filter.standard.allows(rgb: nearRed, hsl: hsl))
        XCTAssertTrue(Palette.Filter.lightnessOnly.allows(rgb: nearRed, hsl: hsl))

        for extreme: UInt32 in [0x000000, 0xFFFFFF, 0x080808, 0xF8F8F8] {
            XCTAssertFalse(Palette.Filter.lightnessOnly.allows(rgb: extreme, hsl: HSL(rgb: extreme)), String(extreme, radix: 16))
        }
    }

    func testTargetRangesMatchAndroidXDefaults() {
        XCTAssertEqual(Palette.Target.vibrant.saturationRange.minimum, 0.35)
        XCTAssertEqual(Palette.Target.vibrant.saturationRange.target, 1)
        XCTAssertEqual(Palette.Target.muted.saturationRange.target, 0.3)
        XCTAssertEqual(Palette.Target.muted.saturationRange.maximum, 0.4)
        XCTAssertEqual(Palette.Target.lightVibrant.lightnessRange.target, 0.74)
        XCTAssertEqual(Palette.Target.vibrant.lightnessRange.target, 0.5)
        XCTAssertEqual(Palette.Target.darkMuted.lightnessRange.target, 0.26)
        XCTAssertEqual(Palette.Target.darkMuted.lightnessRange.maximum, 0.45)
    }

    func testSwatchColorRoundTrips() {
        let swatch = Palette.Swatch(rgb: 0x2070D8, population: 3)
        XCTAssertEqual(swatch.red, 0x20)
        XCTAssertEqual(swatch.green, 0x70)
        XCTAssertEqual(swatch.blue, 0xD8)
        XCTAssertEqual(swatch.color.rgb, 0x2070D8)
    }
}
