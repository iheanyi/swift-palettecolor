// PaletteColor
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import PaletteColor

struct PaletteSchemeTests {
    private let configuration = PaletteScheme.Configuration.default

    @Test func accentsRemainReadableAcrossEveryWashStop() {
        for scheme in [
            PaletteScheme(seed: RGBColor(red: 1, green: 0.95, blue: 0.05)),
            PaletteScheme(seed: RGBColor(red: 0.05, green: 0.08, blue: 0.7)),
            PaletteScheme(seed: RGBColor(red: 0.95, green: 0.1, blue: 0.12)),
            PaletteScheme(seed: .white),
            PaletteScheme(seed: .black),
        ] {
            for stop in scheme.washStops {
                #expect(scheme.accent.contrast(with: stop) >= 4.5)
            }
            #expect(scheme.accent.contrast(with: scheme.onAccent) >= 4.5)
        }
    }

    @Test func textRolesMatchNeutralsAndRemainReadableAcrossWash() {
        let darkWash = PaletteScheme(
            seed: RGBColor(red: 0.25, green: 0.18, blue: 0.30),
            darkMuted: RGBColor(red: 0.08, green: 0.06, blue: 0.10)
        )
        #expect(darkWash.primaryText == configuration.onSurface)
        #expect(darkWash.secondaryText == configuration.onSurfaceVariant)

        for scheme in [
            darkWash,
            PaletteScheme(
                seed: RGBColor(red: 1, green: 0.95, blue: 0.2),
                darkMuted: RGBColor(red: 0.95, green: 0.85, blue: 0.25),
                vibrant: RGBColor(red: 1, green: 0.9, blue: 0.1)
            ),
        ] {
            for stop in scheme.washStops {
                #expect(scheme.primaryText.contrast(with: stop) >= 4.5)
                #expect(scheme.secondaryText.contrast(with: stop) >= 4.5)
            }
        }
    }

    @Test func monochromeUsesFallbackAccentAndContainersStayDark() {
        let monochrome = PaletteScheme(seed: RGBColor(red: 0.8, green: 0.8, blue: 0.8))
        #expect(monochrome.accent == configuration.fallbackAccent)
        #expect(monochrome.secondaryContainer.luminance < monochrome.primaryContainer.luminance)
        #expect(monochrome.primaryContainer.luminance < 0.06)
    }

    @Test func washStopsEndOnSurfaceAndFallBackToTintedSeedWithoutDarkMuted() {
        let scheme = PaletteScheme(seed: RGBColor(rgb: 0x2070D8))
        #expect(scheme.washStops.count == 3)
        #expect(scheme.washStops.last == configuration.surface)
        #expect(scheme.darkMuted == scheme.seed.mixed(with: configuration.surface, fraction: 0.65))
        #expect(scheme.vibrant == scheme.seed)
        #expect(scheme.lightMuted == nil)
        #expect(scheme.lightVibrant == nil)
    }

    @Test func schemeFromPaletteChoosesLightestColorfulSeedAndCarriesRoleSwatches() throws {
        let pixels: [UInt32] = [
            0x2070D8, 0x2070D8, 0x2070D8,
            0xD020C0, 0xD020C0,
            0x5C8A60, 0x5C8A60, 0x5C8A60, 0x5C8A60,
            0xA0A0A0, 0xA0A0A0, 0xA0A0A0,
            0x101010,
        ]
        let palette = Palette.generate(pixels: pixels)
        let scheme = try #require(PaletteScheme(palette: palette))

        // No lightVibrant in this fixture, so lightMuted (0xA0A0A0) becomes the seed.
        #expect(scheme.seed.rgb == 0xA0A0A0)
        #expect(scheme.lightMuted?.rgb == 0xA0A0A0)
        #expect(scheme.vibrant.rgb == 0x2070D8)
        #expect(scheme.darkMuted.rgb == 0x101010)
        #expect(scheme.lightVibrant == nil)
        // The grey lightMuted control seed has no chroma, so the accent falls back.
        #expect(scheme.accent == configuration.fallbackAccent)
    }

    @Test func schemeFromPaletteFallsBackToDominantWhenNoRoleMatches() throws {
        // A single dark-vibrant color matches no light/normal target, so seed == dominant.
        let pixels = Array(repeating: UInt32(0x100060), count: 8)
        let palette = Palette.generate(pixels: pixels)
        #expect(palette.lightVibrant == nil)
        #expect(palette.lightMuted == nil)
        #expect(palette.vibrant == nil)
        let scheme = try #require(PaletteScheme(palette: palette))
        #expect(scheme.seed == palette.dominant?.color)
    }

    @Test func schemeFromPixelsRetriesWithLightnessOnlyFilter() throws {
        let nearRed = Array(repeating: UInt32(0xD06040), count: 12)
        #expect(PaletteScheme(palette: Palette.generate(pixels: nearRed)) == nil)
        let scheme = try #require(PaletteScheme(pixels: nearRed))
        #expect(scheme.seed.rgb == 0xD06040)
        for stop in scheme.washStops {
            #expect(scheme.accent.contrast(with: stop) >= 4.5)
        }
    }

    @Test func schemeIsNilForEmptyPalette() {
        #expect(PaletteScheme(palette: .empty) == nil)
        #expect(PaletteScheme(pixels: Array(repeating: UInt32(0xFFFFFF), count: 4)) == nil)
    }

    @Test func neutralSchemeIsReadable() {
        let neutral = PaletteScheme.neutral
        #expect(neutral.seed == RGBColor(red: 0.25, green: 0.25, blue: 0.25))
        #expect(neutral.accent == configuration.fallbackAccent)
        for stop in neutral.washStops {
            #expect(neutral.primaryText.contrast(with: stop) >= 4.5)
        }
    }

    @Test func lightConfigurationKeepsAccentAndTextReadable() {
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
            #expect(scheme.washStops.last == .white)
            for stop in scheme.washStops {
                #expect(scheme.accent.contrast(with: stop) >= 4.5, "accent for \(seed)")
                #expect(scheme.primaryText.contrast(with: stop) >= 4.5, "primary for \(seed)")
                #expect(scheme.secondaryText.contrast(with: stop) >= 4.5, "secondary for \(seed)")
            }
            #expect(scheme.accent.contrast(with: scheme.onAccent) >= 4.5)
        }

        let yellow = PaletteScheme(seed: RGBColor(rgb: 0xFFEE55), configuration: light)
        #expect(yellow.accent.luminance < RGBColor(rgb: 0xFFEE55).luminance)
        #expect(yellow.onAccent == .white)
    }

    @Test func primaryTextIsLiftedWhenOnSurfaceIsNotReadableOnLightWash() {
        // A mid grey onSurface reads fine on plain white but not on the tinted wash stops.
        let light = PaletteScheme.Configuration(
            surface: .white,
            fallbackAccent: RGBColor(rgb: 0x0077AA),
            onSurface: RGBColor(rgb: 0x777777),
            onSurfaceVariant: RGBColor(rgb: 0x999999)
        )
        let scheme = PaletteScheme(seed: .black, configuration: light)
        #expect(!(scheme.washStops.allSatisfy { light.onSurface.contrast(with: $0) >= 4.5 }))

        #expect(scheme.primaryText != light.onSurface)
        #expect(scheme.primaryText.luminance < light.onSurface.luminance)
        for stop in scheme.washStops {
            #expect(scheme.primaryText.contrast(with: stop) >= 4.5)
            #expect(scheme.secondaryText.contrast(with: stop) >= 4.5)
        }
        // Secondary falls through onSurfaceVariant to the same lifted onSurface.
        #expect(scheme.secondaryText == scheme.primaryText)
    }

    @Test func primaryTextIsLiftedTowardWhiteOnDarkWashWhenOnSurfaceIsDim() {
        let dim = PaletteScheme.Configuration(
            onSurface: RGBColor(rgb: 0x707070), onSurfaceVariant: RGBColor(rgb: 0x606060)
        )
        let scheme = PaletteScheme(
            seed: RGBColor(rgb: 0x2070D8),
            darkMuted: RGBColor(rgb: 0x203050),
            configuration: dim
        )
        #expect(scheme.primaryText != dim.onSurface)
        #expect(scheme.primaryText.luminance > dim.onSurface.luminance)
        for stop in scheme.washStops {
            #expect(scheme.primaryText.contrast(with: stop) >= 4.5)
        }
    }

    @Test func primaryTextStaysOnSurfaceWhenAlreadyReadable() {
        let scheme = PaletteScheme(seed: RGBColor(rgb: 0x2070D8), darkMuted: RGBColor(rgb: 0x101020))
        #expect(scheme.primaryText == configuration.onSurface)
    }

    @Test func customConfigurationDrivesSurfaceAndThresholds() {
        let custom = PaletteScheme.Configuration(
            surface: RGBColor(rgb: 0x000000),
            fallbackAccent: RGBColor(rgb: 0xFF00FF),
            onSurface: .white,
            onSurfaceVariant: RGBColor(rgb: 0xCCCCCC),
            minimumContrast: 7,
            minimumAccentChroma: 0.5
        )
        let scheme = PaletteScheme(seed: RGBColor(red: 0.2, green: 0.5, blue: 0.6), configuration: custom)
        #expect(scheme.surface == .black)
        #expect(scheme.washStops.last == .black)
        // chroma 0.4 < 0.5, so the fallback accent is used and lifted to 7:1.
        for stop in scheme.washStops {
            #expect(scheme.accent.contrast(with: stop) >= 7)
        }
        #expect(scheme.accent == custom.fallbackAccent.readable(on: scheme.washStops, minimum: 7))
        #expect(scheme.primaryText == .white)
    }
}
