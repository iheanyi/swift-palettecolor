// PaletteColor
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import PaletteColor

struct MediaArtworkSchemeTests {
    private let lime: UInt32 = 0xA8E63C   // HCT hue ≈ 129
    private let pink: UInt32 = 0xE85CA0   // HCT hue ≈ 355
    private let brandCyan: UInt32 = 0x6FD8E8

    private func field(_ first: UInt32, share: Int, _ second: UInt32, count: Int = 100) -> [UInt32] {
        let firstCount = count * share / 100
        return Array(repeating: first, count: firstCount) + Array(repeating: second, count: count - firstCount)
    }

    // MARK: HCT

    @Test func hCTMatchesMaterialColorUtilitiesReferenceValues() {
        // Reference values from material-color-utilities' HCT tests (identical across ports).
        let red = HCT(rgb: 0xFF0000)
        #expect(abs(red.hue - 27.408) <= 0.01)
        #expect(abs(red.chroma - 113.358) <= 0.01)
        #expect(abs(red.tone - 53.233) <= 0.01)

        let green = HCT(rgb: 0x00FF00)
        #expect(abs(green.hue - 142.140) <= 0.01)
        #expect(abs(green.chroma - 108.410) <= 0.01)
        #expect(abs(green.tone - 87.737) <= 0.01)

        let blue = HCT(rgb: 0x0000FF)
        #expect(abs(blue.hue - 282.788) <= 0.01)
        #expect(abs(blue.chroma - 87.231) <= 0.01)
        #expect(abs(blue.tone - 32.303) <= 0.01)

        let white = HCT(.white)
        #expect(abs(white.chroma - 2.869) <= 0.01)
        #expect(abs(white.tone - 100) <= 0.001)
        #expect(abs(HCT(.black).tone - 0) <= 0.001)
    }

    @Test func hCTSolverRoundTripsAndClampsChromaToGamut() {
        #expect(HCT(hue: 282.788, chroma: 87.231, tone: 32.303).color.rgb == 0x0000FF)

        let impossible = HCT(hue: 27, chroma: 200, tone: 50).color
        let measured = HCT(impossible)
        #expect(abs(measured.tone - 50) <= 0.5)
        #expect(abs(measured.hue - 27) <= 1)
        #expect(measured.chroma > 100)
        #expect(measured.chroma < 120)

        let grey = HCT(hue: 120, chroma: 0, tone: 60).color
        #expect(grey.red == grey.green)
        #expect(grey.green == grey.blue)
        #expect(abs(HCT(grey).tone - 60) <= 0.5)
    }

    // MARK: Roles

    @Test func solidColorSeedsAccentAtToneNinetyOfSeedHueAndChroma() {
        let scheme = MediaArtworkScheme(pixels: Array(repeating: 0x2070D8, count: 64))
        #expect(scheme.seed.rgb == 0x2070D8)
        let hue = scheme.seedHCT.hue, chroma = scheme.seedHCT.chroma
        #expect(abs(hue - 264.25) <= 0.05)
        #expect(abs(chroma - 60.58) <= 0.05)

        // accent = A1.tone(90) exactly, with A1 = TonalPalette(h, c).
        #expect(scheme.accent == HCT(hue: hue, chroma: chroma, tone: 90).color)
        let accent = HCT(scheme.accent)
        #expect(abs(accent.tone - 90) <= 0.5)
        #expect(abs(accent.hue - hue) <= 3)

        let neutral = chroma / 8
        #expect(scheme.onAccent == HCT(hue: hue, chroma: neutral, tone: 10).color)
        #expect(scheme.accentSecondary == HCT(hue: hue, chroma: chroma, tone: 80).color)
        #expect(scheme.textPrimary == HCT(hue: hue, chroma: neutral, tone: 95).color)
        #expect(scheme.textSecondary == HCT(hue: hue, chroma: neutral + 4, tone: 80).color)
        #expect(scheme.textTertiary == HCT(hue: hue, chroma: neutral + 4, tone: 60).color)
        #expect(scheme.surface == HCT(hue: hue, chroma: max(chroma - 32, chroma / 2), tone: 20).color)
        #expect(scheme.scrimSurface == HCT(hue: hue, chroma: max(chroma - 32, chroma / 2), tone: 30).color)
        #expect(scheme.scrimAccent == HCT(hue: hue, chroma: chroma, tone: 30).color)
        #expect(scheme.isChromatic)
    }

    @Test func isChromaticUsesScoreCutoffChroma() {
        #expect(MediaArtworkScheme(seed: RGBColor(rgb: 0x2070D8)).isChromatic)
        #expect(!(MediaArtworkScheme(seed: .white).isChromatic))      // chroma 2.87
        #expect(!(MediaArtworkScheme(seed: .black).isChromatic))
        #expect(!(MediaArtworkScheme(seed: RGBColor(rgb: 0x808080)).isChromatic))
        #expect(!(MediaArtworkScheme(seed: HCT(hue: 100, chroma: 4.5, tone: 50).color).isChromatic))
        #expect(MediaArtworkScheme(seed: HCT(hue: 100, chroma: 6, tone: 50).color).isChromatic)
        #expect(MediaArtworkScheme.chromaCutoff == 5)
    }

    @Test func toneOfRoleReproducesTheFixedRoles() {
        let scheme = MediaArtworkScheme(seed: RGBColor(rgb: 0xD02020))
        #expect(scheme.tone(90, of: .accent) == scheme.accent)
        #expect(scheme.tone(80, of: .accent) == scheme.accentSecondary)
        #expect(scheme.tone(10, of: .neutral) == scheme.onAccent)
        #expect(scheme.tone(95, of: .neutral) == scheme.textPrimary)
        #expect(scheme.tone(80, of: .neutralVariant) == scheme.textSecondary)
        #expect(scheme.tone(60, of: .neutralVariant) == scheme.textTertiary)
        #expect(scheme.tone(20, of: .accentVariant) == scheme.surface)
        #expect(scheme.tone(30, of: .accentVariant) == scheme.scrimSurface)
        #expect(scheme.tone(30, of: .accent) == scheme.scrimAccent)
        // Low-chroma seeds keep the accent-variant palette at half chroma rather than zero.
        let pale = MediaArtworkScheme(seed: HCT(hue: 200, chroma: 20, tone: 50).color)
        #expect(abs(HCT(pale.tone(50, of: .accentVariant)).chroma - 10) <= 1)
    }

    @Test func rolesAreOrderedByToneAndReadable() {
        for seed: UInt32 in [0x2070D8, 0xD02020, 0xA8E63C, 0xFFFFFF, 0x000000, 0x808080] {
            let scheme = MediaArtworkScheme(seed: RGBColor(rgb: seed))
            let tones = [
                scheme.textPrimary, scheme.accent, scheme.textSecondary, scheme.textTertiary,
                scheme.scrimSurface, scheme.surface, scheme.onAccent,
            ]
                .map { HCT($0).tone }
            #expect(abs(HCT(scheme.scrimAccent).tone - 30) <= 0.5)
            #expect(tones == tones.sorted(by: >), "roles for \(String(seed, radix: 16))")
            #expect(scheme.accent.contrast(with: scheme.onAccent) >= 7, "\(String(seed, radix: 16))")
            #expect(scheme.textPrimary.contrast(with: scheme.surface) >= 7, "\(String(seed, radix: 16))")
            #expect(scheme.accent.contrast(with: scheme.surface) >= 4.5, "\(String(seed, radix: 16))")
        }
    }

    // MARK: Seed selection

    @Test func blackAndWhiteArtworkKeepsGreyAccentInsteadOfBrandColor() {
        let fixtures: [[UInt32]] = [
            Array(repeating: 0x000000, count: 40) + Array(repeating: 0xFFFFFF, count: 24)
                + Array(repeating: 0x808080, count: 30),
            Array(repeating: 0x303030, count: 40) + Array(repeating: 0xC0C0C0, count: 24),
            Array(repeating: 0x000000, count: 10),
        ]
        for pixels in fixtures {
            let scheme = MediaArtworkScheme(pixels: pixels)
            #expect(scheme.seed != MediaArtworkScheme.fallbackSeed)
            #expect(scheme.seedHCT.chroma < 5)
            let accent = HCT(scheme.accent)
            #expect(accent.chroma < 5)
            #expect(abs(accent.tone - 90) <= 0.5)
            #expect(scheme.accent.rgb != brandCyan)
            #expect(scheme.accent.chroma < 0.02)
            #expect(!scheme.isChromatic)
        }
    }

    @Test func seedFollowsAreaBetweenTwoFields() {
        let limeHeavy = MediaArtworkScheme.seedColor(pixels: field(lime, share: 70, pink))
        #expect(abs(HCT(limeHeavy).hue - 129) <= 3)
        let pinkHeavy = MediaArtworkScheme.seedColor(pixels: field(pink, share: 70, lime))
        #expect(abs(HCT(pinkHeavy).hue - 355) <= 3)

        let width = 300, height = 200
        var bitmap = [UInt32]()
        for _ in 0..<height {
            for x in 0..<width { bitmap.append(x < width * 7 / 10 ? lime : pink) }
        }
        let scheme = MediaArtworkScheme(pixels: bitmap, width: width, height: height)
        #expect(abs(scheme.seedHCT.hue - 129) <= 3)
        #expect(abs(HCT(scheme.accent).tone - 90) <= 0.5)
    }

    @Test func fallbackSeedIsAppleSystemBlueNotGoogleBlue() {
        #expect(MediaArtworkScheme.fallbackSeed.rgb == 0x007AFF)
        #expect(MediaArtworkScheme.fallbackSeed.rgb != 0x1B6EF3)
        #expect(MediaArtworkScheme.fallbackSeed.rgb != brandCyan)
    }

    @Test func emptyPixelsFallBackToAppleSystemBlue() {
        let scheme = MediaArtworkScheme(pixels: [])
        #expect(scheme.seed.rgb == 0x007AFF)
        #expect(scheme.seed == MediaArtworkScheme.fallbackSeed)
        #expect(MediaArtworkScheme.seedColor(pixels: []).rgb == 0x007AFF)
        #expect(abs(HCT(scheme.accent).tone - 90) <= 0.5)

        // Callers (for example the UIKit path with the live systemBlue) can pass their own fallback.
        let dark = RGBColor(rgb: 0x0A84FF)
        #expect(MediaArtworkScheme(pixels: [], fallbackSeed: dark).seed == dark)
        #expect(MediaArtworkScheme(pixels: [], width: 0, height: 0, fallbackSeed: dark).seed == dark)
        // The fallback never overrides real pixels.
        #expect(MediaArtworkScheme(pixels: [lime], fallbackSeed: dark).seed.rgb == lime)
    }

    @Test func missingArtworkSchemeIsTheBrandSeedsN1Tone90Gray() {
        // Android: fromSeed(Hct.from(CamperPlaybackAccent.hue, CamperPlaybackAccent.chroma / 8, 50)).
        #expect(MediaArtworkScheme.camperPlaybackAccentRGB == brandCyan)
        let brand = HCT(rgb: MediaArtworkScheme.camperPlaybackAccentRGB)
        #expect(abs(brand.hue - 209.389) <= 0.01)
        #expect(abs(brand.chroma - 42.016) <= 0.01)

        let scheme = MediaArtworkScheme.missingArtwork
        #expect(scheme == MediaArtworkScheme(seed: HCT(hue: brand.hue, chroma: brand.chroma / 8, tone: 50).color))
        // Values resolved by the Android twin at 504e230.
        #expect(scheme.seed.rgb == 0x737879)
        #expect(abs(scheme.seedHCT.chroma - 5.25) <= 0.01)
        #expect(abs(scheme.seedHCT.tone - 50) <= 0.1)
        #expect(scheme.isChromatic)
        #expect(scheme.accent.rgb == 0xDFE3E4)

        #expect(scheme.accent.rgb != brandCyan)
        #expect(scheme.seed != MediaArtworkScheme.fallbackSeed)
        #expect(scheme != MediaArtworkScheme.unreadableArtwork)
        let accent = HCT(scheme.accent)
        #expect(abs(accent.tone - 90) <= 0.5)
        #expect(accent.chroma < 6)
        #expect(scheme.accent.chroma < 0.03)   // near-grey in sRGB too
    }

    @Test func unreadableArtworkIsSeededWithAppleSystemBlue() {
        let scheme = MediaArtworkScheme.unreadableArtwork
        #expect(scheme.seed.rgb == 0x007AFF)
        #expect(scheme == MediaArtworkScheme(seed: MediaArtworkScheme.fallbackSeed))
        #expect(scheme == MediaArtworkScheme(pixels: []))
        #expect(scheme != .missingArtwork)
    }

    @Test func schemeIsDeterministicAndHashable() {
        let pixels = field(lime, share: 55, pink)
        #expect(MediaArtworkScheme(pixels: pixels) == MediaArtworkScheme(pixels: pixels))
        #expect(Set([MediaArtworkScheme(pixels: pixels), MediaArtworkScheme(pixels: pixels)]).count == 1)
    }

    // MARK: WallpaperColors downscale

    @Test func downscaleMatchesWallpaperColorsOptimalSize() {
        let small = Array(repeating: lime, count: 112 * 112)
        #expect(MediaArtworkScheme.downscaled(pixels: small, width: 112, height: 112) == small)

        let square = Array(repeating: lime, count: 224 * 224)
        #expect(MediaArtworkScheme.downscaled(pixels: square, width: 224, height: 224).count == (112 * 112))

        // 300×200: scale = sqrt(12544 / 60000), dimensions truncated → 137×91 (not ceil'd 138×92).
        var bitmap = [UInt32]()
        for _ in 0..<200 {
            for x in 0..<300 { bitmap.append(x < 210 ? lime : pink) }
        }
        let scaled = MediaArtworkScheme.downscaled(pixels: bitmap, width: 300, height: 200)
        #expect(scaled.count == (137 * 91))
        let limeShare = Double(scaled.filter { $0 == lime }.count) / Double(scaled.count)
        #expect(abs(limeShare - 0.7) <= 0.02)
        #expect(Set(scaled) == [lime, pink])
    }

    @Test func downscaleNeverCollapsesADimensionToZero() {
        let strip = Array(repeating: pink, count: 20000)
        let scaled = MediaArtworkScheme.downscaled(pixels: strip, width: 20000, height: 1)
        #expect(scaled.count > 0)
        #expect(scaled.allSatisfy { $0 == pink })
    }

    @Test func maxColorsClampsAreaOverSixteen() {
        #expect(MediaArtworkScheme.maxColors(forArea: 0) == 5)
        #expect(MediaArtworkScheme.maxColors(forArea: 16) == 5)
        #expect(MediaArtworkScheme.maxColors(forArea: 800) == 50)
        #expect(MediaArtworkScheme.maxColors(forArea: 112 * 112) == 128)
        #expect(MediaArtworkScheme.maxColors(forArea: 1_000_000) == 128)
    }
}
