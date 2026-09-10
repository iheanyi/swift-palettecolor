// PaletteColor
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PaletteColor

final class MediaArtworkSchemeTests: XCTestCase {
    private let lime: UInt32 = 0xA8E63C   // HCT hue ≈ 129
    private let pink: UInt32 = 0xE85CA0   // HCT hue ≈ 355
    private let brandCyan: UInt32 = 0x6FD8E8

    private func field(_ first: UInt32, share: Int, _ second: UInt32, count: Int = 100) -> [UInt32] {
        let firstCount = count * share / 100
        return Array(repeating: first, count: firstCount) + Array(repeating: second, count: count - firstCount)
    }

    // MARK: HCT

    func testHCTMatchesMaterialColorUtilitiesReferenceValues() {
        // Reference values from material-color-utilities' HCT tests (identical across ports).
        let red = HCT(rgb: 0xFF0000)
        XCTAssertEqual(red.hue, 27.408, accuracy: 0.01)
        XCTAssertEqual(red.chroma, 113.358, accuracy: 0.01)
        XCTAssertEqual(red.tone, 53.233, accuracy: 0.01)

        let green = HCT(rgb: 0x00FF00)
        XCTAssertEqual(green.hue, 142.140, accuracy: 0.01)
        XCTAssertEqual(green.chroma, 108.410, accuracy: 0.01)
        XCTAssertEqual(green.tone, 87.737, accuracy: 0.01)

        let blue = HCT(rgb: 0x0000FF)
        XCTAssertEqual(blue.hue, 282.788, accuracy: 0.01)
        XCTAssertEqual(blue.chroma, 87.231, accuracy: 0.01)
        XCTAssertEqual(blue.tone, 32.303, accuracy: 0.01)

        let white = HCT(.white)
        XCTAssertEqual(white.chroma, 2.869, accuracy: 0.01)
        XCTAssertEqual(white.tone, 100, accuracy: 0.001)
        XCTAssertEqual(HCT(.black).tone, 0, accuracy: 0.001)
    }

    func testHCTSolverRoundTripsAndClampsChromaToGamut() {
        XCTAssertEqual(HCT(hue: 282.788, chroma: 87.231, tone: 32.303).color.rgb, 0x0000FF)

        let impossible = HCT(hue: 27, chroma: 200, tone: 50).color
        let measured = HCT(impossible)
        XCTAssertEqual(measured.tone, 50, accuracy: 0.5)
        XCTAssertEqual(measured.hue, 27, accuracy: 1)
        XCTAssertGreaterThan(measured.chroma, 100)
        XCTAssertLessThan(measured.chroma, 120)

        let grey = HCT(hue: 120, chroma: 0, tone: 60).color
        XCTAssertEqual(grey.red, grey.green)
        XCTAssertEqual(grey.green, grey.blue)
        XCTAssertEqual(HCT(grey).tone, 60, accuracy: 0.5)
    }

    // MARK: Roles

    func testSolidColorSeedsAccentAtToneNinetyOfSeedHueAndChroma() {
        let scheme = MediaArtworkScheme(pixels: Array(repeating: 0x2070D8, count: 64))
        XCTAssertEqual(scheme.seed.rgb, 0x2070D8)
        let hue = scheme.seedHCT.hue, chroma = scheme.seedHCT.chroma
        XCTAssertEqual(hue, 264.25, accuracy: 0.05)
        XCTAssertEqual(chroma, 60.58, accuracy: 0.05)

        // accent = A1.tone(90) exactly, with A1 = TonalPalette(h, c).
        XCTAssertEqual(scheme.accent, HCT(hue: hue, chroma: chroma, tone: 90).color)
        let accent = HCT(scheme.accent)
        XCTAssertEqual(accent.tone, 90, accuracy: 0.5)
        XCTAssertEqual(accent.hue, hue, accuracy: 3)

        let neutral = chroma / 8
        XCTAssertEqual(scheme.onAccent, HCT(hue: hue, chroma: neutral, tone: 10).color)
        XCTAssertEqual(scheme.accentSecondary, HCT(hue: hue, chroma: chroma, tone: 80).color)
        XCTAssertEqual(scheme.textPrimary, HCT(hue: hue, chroma: neutral, tone: 95).color)
        XCTAssertEqual(scheme.textSecondary, HCT(hue: hue, chroma: neutral + 4, tone: 80).color)
        XCTAssertEqual(scheme.textTertiary, HCT(hue: hue, chroma: neutral + 4, tone: 60).color)
        XCTAssertEqual(scheme.surface, HCT(hue: hue, chroma: max(chroma - 32, chroma / 2), tone: 20).color)
        XCTAssertEqual(scheme.scrimSurface, HCT(hue: hue, chroma: max(chroma - 32, chroma / 2), tone: 30).color)
        XCTAssertEqual(scheme.scrimAccent, HCT(hue: hue, chroma: chroma, tone: 30).color)
        XCTAssertTrue(scheme.isChromatic)
    }

    func testIsChromaticUsesScoreCutoffChroma() {
        XCTAssertTrue(MediaArtworkScheme(seed: RGBColor(rgb: 0x2070D8)).isChromatic)
        XCTAssertFalse(MediaArtworkScheme(seed: .white).isChromatic)      // chroma 2.87
        XCTAssertFalse(MediaArtworkScheme(seed: .black).isChromatic)
        XCTAssertFalse(MediaArtworkScheme(seed: RGBColor(rgb: 0x808080)).isChromatic)
        XCTAssertFalse(MediaArtworkScheme(seed: HCT(hue: 100, chroma: 4.5, tone: 50).color).isChromatic)
        XCTAssertTrue(MediaArtworkScheme(seed: HCT(hue: 100, chroma: 6, tone: 50).color).isChromatic)
        XCTAssertEqual(MediaArtworkScheme.chromaCutoff, 5)
    }

    func testToneOfRoleReproducesTheFixedRoles() {
        let scheme = MediaArtworkScheme(seed: RGBColor(rgb: 0xD02020))
        XCTAssertEqual(scheme.tone(90, of: .accent), scheme.accent)
        XCTAssertEqual(scheme.tone(80, of: .accent), scheme.accentSecondary)
        XCTAssertEqual(scheme.tone(10, of: .neutral), scheme.onAccent)
        XCTAssertEqual(scheme.tone(95, of: .neutral), scheme.textPrimary)
        XCTAssertEqual(scheme.tone(80, of: .neutralVariant), scheme.textSecondary)
        XCTAssertEqual(scheme.tone(60, of: .neutralVariant), scheme.textTertiary)
        XCTAssertEqual(scheme.tone(20, of: .accentVariant), scheme.surface)
        XCTAssertEqual(scheme.tone(30, of: .accentVariant), scheme.scrimSurface)
        XCTAssertEqual(scheme.tone(30, of: .accent), scheme.scrimAccent)
        // Low-chroma seeds keep the accent-variant palette at half chroma rather than zero.
        let pale = MediaArtworkScheme(seed: HCT(hue: 200, chroma: 20, tone: 50).color)
        XCTAssertEqual(HCT(pale.tone(50, of: .accentVariant)).chroma, 10, accuracy: 1)
    }

    func testRolesAreOrderedByToneAndReadable() {
        for seed: UInt32 in [0x2070D8, 0xD02020, 0xA8E63C, 0xFFFFFF, 0x000000, 0x808080] {
            let scheme = MediaArtworkScheme(seed: RGBColor(rgb: seed))
            let tones = [scheme.textPrimary, scheme.accent, scheme.textSecondary, scheme.textTertiary, scheme.scrimSurface, scheme.surface, scheme.onAccent]
                .map { HCT($0).tone }
            XCTAssertEqual(HCT(scheme.scrimAccent).tone, 30, accuracy: 0.5)
            XCTAssertEqual(tones, tones.sorted(by: >), "roles for \(String(seed, radix: 16))")
            XCTAssertGreaterThanOrEqual(scheme.accent.contrast(with: scheme.onAccent), 7, "\(String(seed, radix: 16))")
            XCTAssertGreaterThanOrEqual(scheme.textPrimary.contrast(with: scheme.surface), 7, "\(String(seed, radix: 16))")
            XCTAssertGreaterThanOrEqual(scheme.accent.contrast(with: scheme.surface), 4.5, "\(String(seed, radix: 16))")
        }
    }

    // MARK: Seed selection

    func testBlackAndWhiteArtworkKeepsGreyAccentInsteadOfBrandColor() {
        let fixtures: [[UInt32]] = [
            Array(repeating: 0x000000, count: 40) + Array(repeating: 0xFFFFFF, count: 24) + Array(repeating: 0x808080, count: 30),
            Array(repeating: 0x303030, count: 40) + Array(repeating: 0xC0C0C0, count: 24),
            Array(repeating: 0x000000, count: 10),
        ]
        for pixels in fixtures {
            let scheme = MediaArtworkScheme(pixels: pixels)
            XCTAssertNotEqual(scheme.seed, MediaArtworkScheme.fallbackSeed)
            XCTAssertLessThan(scheme.seedHCT.chroma, 5)
            let accent = HCT(scheme.accent)
            XCTAssertLessThan(accent.chroma, 5)
            XCTAssertEqual(accent.tone, 90, accuracy: 0.5)
            XCTAssertNotEqual(scheme.accent.rgb, brandCyan)
            XCTAssertLessThan(scheme.accent.chroma, 0.02)
            XCTAssertFalse(scheme.isChromatic)
        }
    }

    func testSeedFollowsAreaBetweenTwoFields() {
        let limeHeavy = MediaArtworkScheme.seedColor(pixels: field(lime, share: 70, pink))
        XCTAssertEqual(HCT(limeHeavy).hue, 129, accuracy: 3)
        let pinkHeavy = MediaArtworkScheme.seedColor(pixels: field(pink, share: 70, lime))
        XCTAssertEqual(HCT(pinkHeavy).hue, 355, accuracy: 3)

        let width = 300, height = 200
        var bitmap = [UInt32]()
        for _ in 0..<height {
            for x in 0..<width { bitmap.append(x < width * 7 / 10 ? lime : pink) }
        }
        let scheme = MediaArtworkScheme(pixels: bitmap, width: width, height: height)
        XCTAssertEqual(scheme.seedHCT.hue, 129, accuracy: 3)
        XCTAssertEqual(HCT(scheme.accent).tone, 90, accuracy: 0.5)
    }

    func testEmptyPixelsFallBackToGoogleBlue() {
        let scheme = MediaArtworkScheme(pixels: [])
        XCTAssertEqual(scheme.seed.rgb, 0x1B6EF3)
        XCTAssertEqual(scheme.seed, MediaArtworkScheme.fallbackSeed)
        XCTAssertEqual(HCT(scheme.accent).tone, 90, accuracy: 0.5)
    }

    func testMissingArtworkIsMutedNeutral() {
        let scheme = MediaArtworkScheme.missingArtwork
        // Same construction as Android's MissingArtwork: fromSeed(Hct(coolHue, smallChroma, 50)).
        XCTAssertEqual(scheme, MediaArtworkScheme(seed: HCT(hue: 209, chroma: 4, tone: 50).color))
        XCTAssertEqual(scheme.seedHCT.tone, 50, accuracy: 0.5)
        XCTAssertFalse(scheme.isChromatic)
        XCTAssertNotEqual(scheme.accent.rgb, brandCyan)
        XCTAssertNotEqual(scheme.seed, MediaArtworkScheme.fallbackSeed)
        let accent = HCT(scheme.accent)
        XCTAssertEqual(accent.tone, 90, accuracy: 0.5)
        XCTAssertLessThan(accent.chroma, 5)
        XCTAssertLessThan(scheme.accent.chroma, 0.03)   // near-grey in sRGB too
        XCTAssertEqual(HCT(scheme.surface).tone, 20, accuracy: 0.5)
        XCTAssertLessThan(HCT(scheme.surface).chroma, 5)
    }

    func testSchemeIsDeterministicAndHashable() {
        let pixels = field(lime, share: 55, pink)
        XCTAssertEqual(MediaArtworkScheme(pixels: pixels), MediaArtworkScheme(pixels: pixels))
        XCTAssertEqual(Set([MediaArtworkScheme(pixels: pixels), MediaArtworkScheme(pixels: pixels)]).count, 1)
    }

    // MARK: WallpaperColors downscale

    func testDownscaleMatchesWallpaperColorsOptimalSize() {
        let small = Array(repeating: lime, count: 112 * 112)
        XCTAssertEqual(MediaArtworkScheme.downscaled(pixels: small, width: 112, height: 112), small)

        let square = Array(repeating: lime, count: 224 * 224)
        XCTAssertEqual(MediaArtworkScheme.downscaled(pixels: square, width: 224, height: 224).count, 112 * 112)

        // 300×200: scale = sqrt(12544 / 60000), dimensions truncated → 137×91 (not ceil'd 138×92).
        var bitmap = [UInt32]()
        for _ in 0..<200 {
            for x in 0..<300 { bitmap.append(x < 210 ? lime : pink) }
        }
        let scaled = MediaArtworkScheme.downscaled(pixels: bitmap, width: 300, height: 200)
        XCTAssertEqual(scaled.count, 137 * 91)
        let limeShare = Double(scaled.filter { $0 == lime }.count) / Double(scaled.count)
        XCTAssertEqual(limeShare, 0.7, accuracy: 0.02)
        XCTAssertEqual(Set(scaled), [lime, pink])
    }

    func testDownscaleNeverCollapsesADimensionToZero() {
        let strip = Array(repeating: pink, count: 20000)
        let scaled = MediaArtworkScheme.downscaled(pixels: strip, width: 20000, height: 1)
        XCTAssertGreaterThan(scaled.count, 0)
        XCTAssertTrue(scaled.allSatisfy { $0 == pink })
    }

    func testMaxColorsClampsAreaOverSixteen() {
        XCTAssertEqual(MediaArtworkScheme.maxColors(forArea: 0), 5)
        XCTAssertEqual(MediaArtworkScheme.maxColors(forArea: 16), 5)
        XCTAssertEqual(MediaArtworkScheme.maxColors(forArea: 800), 50)
        XCTAssertEqual(MediaArtworkScheme.maxColors(forArea: 112 * 112), 128)
        XCTAssertEqual(MediaArtworkScheme.maxColors(forArea: 1_000_000), 128)
    }
}
