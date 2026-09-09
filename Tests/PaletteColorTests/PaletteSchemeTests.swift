// PaletteColor
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PaletteColor

final class PaletteSchemeTests: XCTestCase {
    private let configuration = PaletteScheme.Configuration.default

    func testAccentsRemainReadableAcrossEveryWashStop() {
        for scheme in [
            PaletteScheme(seed: RGBColor(red: 1, green: 0.95, blue: 0.05)),
            PaletteScheme(seed: RGBColor(red: 0.05, green: 0.08, blue: 0.7)),
            PaletteScheme(seed: RGBColor(red: 0.95, green: 0.1, blue: 0.12)),
            PaletteScheme(seed: .white),
            PaletteScheme(seed: .black),
        ] {
            for stop in scheme.washStops {
                XCTAssertGreaterThanOrEqual(scheme.accent.contrast(with: stop), 4.5)
            }
            XCTAssertGreaterThanOrEqual(scheme.accent.contrast(with: scheme.onAccent), 4.5)
        }
    }

    func testTextRolesMatchNeutralsAndRemainReadableAcrossWash() {
        let darkWash = PaletteScheme(
            seed: RGBColor(red: 0.25, green: 0.18, blue: 0.30),
            darkMuted: RGBColor(red: 0.08, green: 0.06, blue: 0.10)
        )
        XCTAssertEqual(darkWash.primaryText, configuration.onSurface)
        XCTAssertEqual(darkWash.secondaryText, configuration.onSurfaceVariant)

        for scheme in [
            darkWash,
            PaletteScheme(
                seed: RGBColor(red: 1, green: 0.95, blue: 0.2),
                darkMuted: RGBColor(red: 0.95, green: 0.85, blue: 0.25),
                vibrant: RGBColor(red: 1, green: 0.9, blue: 0.1)
            ),
        ] {
            for stop in scheme.washStops {
                XCTAssertGreaterThanOrEqual(scheme.primaryText.contrast(with: stop), 4.5)
                XCTAssertGreaterThanOrEqual(scheme.secondaryText.contrast(with: stop), 4.5)
            }
        }
    }

    func testMonochromeUsesFallbackAccentAndContainersStayDark() {
        let monochrome = PaletteScheme(seed: RGBColor(red: 0.8, green: 0.8, blue: 0.8))
        XCTAssertEqual(monochrome.accent, configuration.fallbackAccent)
        XCTAssertLessThan(monochrome.secondaryContainer.luminance, monochrome.primaryContainer.luminance)
        XCTAssertLessThan(monochrome.primaryContainer.luminance, 0.06)
    }

    func testWashStopsEndOnSurfaceAndFallBackToTintedSeedWithoutDarkMuted() {
        let scheme = PaletteScheme(seed: RGBColor(rgb: 0x2070D8))
        XCTAssertEqual(scheme.washStops.count, 3)
        XCTAssertEqual(scheme.washStops.last, configuration.surface)
        XCTAssertEqual(scheme.darkMuted, scheme.seed.mixed(with: configuration.surface, fraction: 0.65))
        XCTAssertEqual(scheme.vibrant, scheme.seed)
        XCTAssertNil(scheme.lightMuted)
        XCTAssertNil(scheme.lightVibrant)
    }

    func testSchemeFromPaletteChoosesLightestColorfulSeedAndCarriesRoleSwatches() throws {
        let pixels: [UInt32] = [
            0x2070D8, 0x2070D8, 0x2070D8,
            0xD020C0, 0xD020C0,
            0x5C8A60, 0x5C8A60, 0x5C8A60, 0x5C8A60,
            0xA0A0A0, 0xA0A0A0, 0xA0A0A0,
            0x101010,
        ]
        let palette = Palette.generate(pixels: pixels)
        let scheme = try XCTUnwrap(PaletteScheme(palette: palette))

        // No lightVibrant in this fixture, so lightMuted (0xA0A0A0) becomes the seed.
        XCTAssertEqual(scheme.seed.rgb, 0xA0A0A0)
        XCTAssertEqual(scheme.lightMuted?.rgb, 0xA0A0A0)
        XCTAssertEqual(scheme.vibrant.rgb, 0x2070D8)
        XCTAssertEqual(scheme.darkMuted.rgb, 0x101010)
        XCTAssertNil(scheme.lightVibrant)
        // The grey lightMuted control seed has no chroma, so the accent falls back.
        XCTAssertEqual(scheme.accent, configuration.fallbackAccent)
    }

    func testSchemeFromPaletteFallsBackToDominantWhenNoRoleMatches() throws {
        // A single dark-vibrant color matches no light/normal target, so seed == dominant.
        let pixels = Array(repeating: UInt32(0x100060), count: 8)
        let palette = Palette.generate(pixels: pixels)
        XCTAssertNil(palette.lightVibrant)
        XCTAssertNil(palette.lightMuted)
        XCTAssertNil(palette.vibrant)
        let scheme = try XCTUnwrap(PaletteScheme(palette: palette))
        XCTAssertEqual(scheme.seed, palette.dominant?.color)
    }

    func testSchemeFromPixelsRetriesWithLightnessOnlyFilter() throws {
        let nearRed = Array(repeating: UInt32(0xD06040), count: 12)
        XCTAssertNil(PaletteScheme(palette: Palette.generate(pixels: nearRed)))
        let scheme = try XCTUnwrap(PaletteScheme(pixels: nearRed))
        XCTAssertEqual(scheme.seed.rgb, 0xD06040)
        for stop in scheme.washStops {
            XCTAssertGreaterThanOrEqual(scheme.accent.contrast(with: stop), 4.5)
        }
    }

    func testSchemeIsNilForEmptyPalette() {
        XCTAssertNil(PaletteScheme(palette: .empty))
        XCTAssertNil(PaletteScheme(pixels: Array(repeating: UInt32(0xFFFFFF), count: 4)))
    }

    func testNeutralSchemeIsReadable() {
        let neutral = PaletteScheme.neutral
        XCTAssertEqual(neutral.seed, RGBColor(red: 0.25, green: 0.25, blue: 0.25))
        XCTAssertEqual(neutral.accent, configuration.fallbackAccent)
        for stop in neutral.washStops {
            XCTAssertGreaterThanOrEqual(neutral.primaryText.contrast(with: stop), 4.5)
        }
    }

    func testLightConfigurationKeepsAccentAndTextReadable() {
        let light = PaletteScheme.Configuration(
            surface: .white,
            fallbackAccent: RGBColor(rgb: 0x0077AA),
            onSurface: RGBColor(rgb: 0x1B1B1F),
            onSurfaceVariant: RGBColor(rgb: 0x46464F)
        )
        for seed in [
            RGBColor(rgb: 0xFFEE55),   // pale yellow: must darken toward black
            RGBColor(rgb: 0x6FD8E8),   // pale cyan
            RGBColor(rgb: 0x2070D8),   // mid blue
            RGBColor(rgb: 0xC0C0C0),   // grey: falls back
            .black,
        ] {
            let scheme = PaletteScheme(seed: seed, configuration: light)
            XCTAssertEqual(scheme.washStops.last, .white)
            for stop in scheme.washStops {
                XCTAssertGreaterThanOrEqual(scheme.accent.contrast(with: stop), 4.5, "accent for \(seed)")
                XCTAssertGreaterThanOrEqual(scheme.primaryText.contrast(with: stop), 4.5, "primary for \(seed)")
                XCTAssertGreaterThanOrEqual(scheme.secondaryText.contrast(with: stop), 4.5, "secondary for \(seed)")
            }
            XCTAssertGreaterThanOrEqual(scheme.accent.contrast(with: scheme.onAccent), 4.5)
        }

        let yellow = PaletteScheme(seed: RGBColor(rgb: 0xFFEE55), configuration: light)
        XCTAssertLessThan(yellow.accent.luminance, RGBColor(rgb: 0xFFEE55).luminance)
        XCTAssertEqual(yellow.onAccent, .white)
    }

    func testPrimaryTextIsLiftedWhenOnSurfaceIsNotReadableOnLightWash() {
        // A mid grey onSurface reads fine on plain white but not on the tinted wash stops.
        let light = PaletteScheme.Configuration(
            surface: .white,
            fallbackAccent: RGBColor(rgb: 0x0077AA),
            onSurface: RGBColor(rgb: 0x777777),
            onSurfaceVariant: RGBColor(rgb: 0x999999)
        )
        let scheme = PaletteScheme(seed: .black, configuration: light)
        XCTAssertFalse(scheme.washStops.allSatisfy { light.onSurface.contrast(with: $0) >= 4.5 })

        XCTAssertNotEqual(scheme.primaryText, light.onSurface)
        XCTAssertLessThan(scheme.primaryText.luminance, light.onSurface.luminance)
        for stop in scheme.washStops {
            XCTAssertGreaterThanOrEqual(scheme.primaryText.contrast(with: stop), 4.5)
            XCTAssertGreaterThanOrEqual(scheme.secondaryText.contrast(with: stop), 4.5)
        }
        // Secondary falls through onSurfaceVariant to the same lifted onSurface.
        XCTAssertEqual(scheme.secondaryText, scheme.primaryText)
    }

    func testPrimaryTextIsLiftedTowardWhiteOnDarkWashWhenOnSurfaceIsDim() {
        let dim = PaletteScheme.Configuration(onSurface: RGBColor(rgb: 0x707070), onSurfaceVariant: RGBColor(rgb: 0x606060))
        let scheme = PaletteScheme(
            seed: RGBColor(rgb: 0x2070D8),
            darkMuted: RGBColor(rgb: 0x203050),
            configuration: dim
        )
        XCTAssertNotEqual(scheme.primaryText, dim.onSurface)
        XCTAssertGreaterThan(scheme.primaryText.luminance, dim.onSurface.luminance)
        for stop in scheme.washStops {
            XCTAssertGreaterThanOrEqual(scheme.primaryText.contrast(with: stop), 4.5)
        }
    }

    func testPrimaryTextStaysOnSurfaceWhenAlreadyReadable() {
        let scheme = PaletteScheme(seed: RGBColor(rgb: 0x2070D8), darkMuted: RGBColor(rgb: 0x101020))
        XCTAssertEqual(scheme.primaryText, configuration.onSurface)
    }

    func testCustomConfigurationDrivesSurfaceAndThresholds() {
        let custom = PaletteScheme.Configuration(
            surface: RGBColor(rgb: 0x000000),
            fallbackAccent: RGBColor(rgb: 0xFF00FF),
            onSurface: .white,
            onSurfaceVariant: RGBColor(rgb: 0xCCCCCC),
            minimumContrast: 7,
            minimumAccentChroma: 0.5
        )
        let scheme = PaletteScheme(seed: RGBColor(red: 0.2, green: 0.5, blue: 0.6), configuration: custom)
        XCTAssertEqual(scheme.surface, .black)
        XCTAssertEqual(scheme.washStops.last, .black)
        // chroma 0.4 < 0.5, so the fallback accent is used and lifted to 7:1.
        for stop in scheme.washStops {
            XCTAssertGreaterThanOrEqual(scheme.accent.contrast(with: stop), 7)
        }
        XCTAssertEqual(scheme.accent, custom.fallbackAccent.readable(on: scheme.washStops, minimum: 7))
        XCTAssertEqual(scheme.primaryText, .white)
    }
}
