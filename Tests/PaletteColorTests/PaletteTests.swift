// PaletteColor
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import PaletteColor

struct PaletteTests {
    @Test func matchesAndroidXDefaultPixelVectorAndTargetRoles() {
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

        #expect(result.swatches.map(\.rgb) == [
            0x101010, 0x2070D8, 0x588860, 0xA0A0A0, 0xD020C0, 0xF0F0F0,
        ])
        #expect(result.swatches.map(\.population) == [1, 3, 4, 3, 2, 1])
        #expect(result.dominant?.rgb == 0x588860)
        #expect(result.vibrant?.rgb == 0x2070D8)
        #expect(result.lightMuted?.rgb == 0xA0A0A0)
        #expect(result.muted?.rgb == 0x588860)
        #expect(result.darkMuted?.rgb == 0x101010)
        #expect(result.lightVibrant == nil)
        #expect(result.darkVibrant == nil)
        #expect(result[.vibrant] == result.vibrant)
    }

    @Test func usesLightnessOnlyFallbackOnlyWhenDefaultFilterRejectsEverything() {
        let pixels = Array(repeating: UInt32(0xFFFFFF), count: 12)
        #expect(Palette.generate(pixels: pixels).isEmpty)
        #expect(Palette.generate(pixels: pixels, filter: .lightnessOnly).isEmpty)

        let nearRed = Array(repeating: UInt32(0xD06040), count: 12)
        #expect(Palette.generate(pixels: nearRed).isEmpty)
        #expect(Palette.generate(pixels: nearRed, filter: .lightnessOnly).swatches.count == 1)
        #expect(Palette.generate(pixels: nearRed, retryLightnessOnly: true).swatches.count == 1)
        // The retry is a no-op when the caller already asked for the lightness-only filter.
        let retried = Palette.generate(pixels: nearRed, filter: .lightnessOnly, retryLightnessOnly: true)
        #expect(retried == Palette.generate(pixels: nearRed, filter: .lightnessOnly))
    }

    @Test func retryIsNotUsedWhenStandardFilterSucceeds() {
        let mixed: [UInt32] = Array(repeating: 0x2070D8, count: 4) + Array(repeating: 0xD06040, count: 12)
        let standard = Palette.generate(pixels: mixed)
        let withRetry = Palette.generate(pixels: mixed, retryLightnessOnly: true)
        #expect(standard == withRetry)
        #expect(standard.swatches.map(\.rgb) == [0x2070D8])
    }

    @Test func retryYieldsRolesForRedILineArtwork() {
        let nearRed = Array(repeating: UInt32(0xD06040), count: 12)
        let palette = Palette.generate(pixels: nearRed, retryLightnessOnly: true)
        #expect(palette.dominant?.rgb == 0xD06040)
        #expect(palette.vibrant != nil)
    }

    @Test func emptyInputProducesEmptyPalette() {
        let result = Palette.generate(pixels: [])
        #expect(result.isEmpty)
        #expect(result.dominant == nil)
        #expect(result.selected.isEmpty)
        #expect(result == .empty)
    }

    @Test func medianCutReducesManyDistinctColorsToMaxColors() {
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
        #expect(!result.isEmpty)
        #expect(result.swatches.count <= 16)
        #expect(result.swatches.count > 1)
        #expect((result.swatches.reduce(0) { $0 + $1.population }) <= pixels.count)
        // Every swatch is a 5-bit approximation.
        for swatch in result.swatches {
            #expect((swatch.red & 0x7) == 0)
            #expect((swatch.green & 0x7) == 0)
            #expect((swatch.blue & 0x7) == 0)
        }
        // Population ordering picks the dominant swatch.
        #expect(result.dominant == (result.swatches.max { $0.population < $1.population }))
    }

    @Test func selectedSwatchesAreNotReusedAcrossTargets() {
        let pixels: [UInt32] = Array(repeating: 0x2070D8, count: 10) + Array(repeating: 0x588860, count: 5)
        let result = Palette.generate(pixels: pixels)
        let chosen = result.selected.values.map(\.rgb)
        #expect(Set(chosen).count == chosen.count)
    }

    @Test func hSLMatchesColorUtilsRGBToHSL() {
        let grey = HSL(rgb: 0xA0A0A0)
        #expect(grey.hue == 0)
        #expect(grey.saturation == 0)
        #expect(abs(grey.lightness - (Float(0xA0) / 255)) <= 1e-6)

        let red = HSL(red: 255, green: 0, blue: 0)
        #expect(red.hue == 0)
        #expect(red.saturation == 1)
        #expect(red.lightness == 0.5)

        let blue = HSL(rgb: 0x0000FF)
        #expect(blue.hue == 240)

        let magentaish = HSL(rgb: 0xD020C0)
        #expect(magentaish.hue > 300)
        #expect(magentaish.hue < 320)
    }

    @Test func standardFilterRejectsRedILineButLightnessOnlyKeepsIt() {
        let nearRed: UInt32 = 0xD06040
        let hsl = HSL(rgb: nearRed)
        #expect(hsl.hue >= 10 && hsl.hue <= 37)
        #expect(!Palette.Filter.standard.allows(rgb: nearRed, hsl: hsl))
        #expect(Palette.Filter.lightnessOnly.allows(rgb: nearRed, hsl: hsl))

        for extreme: UInt32 in [0x000000, 0xFFFFFF, 0x080808, 0xF8F8F8] {
            let allowed = Palette.Filter.lightnessOnly.allows(rgb: extreme, hsl: HSL(rgb: extreme))
            #expect(!allowed, "\(String(extreme, radix: 16))")
        }
    }

    @Test func targetRangesMatchAndroidXDefaults() {
        #expect(Palette.Target.vibrant.saturationRange.minimum == 0.35)
        #expect(Palette.Target.vibrant.saturationRange.target == 1)
        #expect(Palette.Target.muted.saturationRange.target == 0.3)
        #expect(Palette.Target.muted.saturationRange.maximum == 0.4)
        #expect(Palette.Target.lightVibrant.lightnessRange.target == 0.74)
        #expect(Palette.Target.vibrant.lightnessRange.target == 0.5)
        #expect(Palette.Target.darkMuted.lightnessRange.target == 0.26)
        #expect(Palette.Target.darkMuted.lightnessRange.maximum == 0.45)
    }

    @Test func swatchColorRoundTrips() {
        let swatch = Palette.Swatch(rgb: 0x2070D8, population: 3)
        #expect(swatch.red == 0x20)
        #expect(swatch.green == 0x70)
        #expect(swatch.blue == 0xD8)
        #expect(swatch.color.rgb == 0x2070D8)
    }
}
