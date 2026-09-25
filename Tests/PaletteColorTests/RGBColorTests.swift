// PaletteColor
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import PaletteColor

struct RGBColorTests {
    @Test func luminanceAndContrastMatchWCAG() {
        #expect(abs(RGBColor.white.luminance - 1) <= 1e-9)
        #expect(abs(RGBColor.black.luminance - 0) <= 1e-9)
        #expect(abs(RGBColor.white.contrast(with: .black) - 21) <= 1e-9)
        #expect(abs(RGBColor.black.contrast(with: .white) - 21) <= 1e-9)
        #expect(abs(RGBColor.white.contrast(with: .white) - 1) <= 1e-9)

        // #767676 on white is the canonical ~4.54:1 WCAG AA boundary grey.
        let grey = RGBColor(rgb: 0x767676)
        #expect(abs(grey.contrast(with: .white) - 4.54) <= 0.01)
    }

    @Test func packedRGBRoundTrips() {
        let color = RGBColor(rgb: 0x2070D8)
        #expect(color.red == (Double(0x20) / 255))
        #expect(color.green == (Double(0x70) / 255))
        #expect(color.blue == (Double(0xD8) / 255))
        #expect(color.rgb == 0x2070D8)
        #expect(RGBColor(red8: 17, green8: 16, blue8: 25).rgb == 0x111019)
        #expect(RGBColor(rgb: 0xFF2070D8).rgb == 0x2070D8)
    }

    @Test func mixedInterpolatesAndClampsFraction() {
        let mid = RGBColor.black.mixed(with: .white, fraction: 0.5)
        #expect(mid == RGBColor(red: 0.5, green: 0.5, blue: 0.5))
        #expect(RGBColor.black.mixed(with: .white, fraction: 2) == .white)
        #expect(RGBColor.black.mixed(with: .white, fraction: -1) == .black)
    }

    @Test func chromaIsZeroForGreys() {
        #expect(RGBColor(red: 0.3, green: 0.3, blue: 0.3).chroma == 0)
        #expect(RGBColor(red: 1, green: 0, blue: 0).chroma == 1)
    }

    @Test func readableReturnsSelfWhenAlreadyLighterAndContrasting() {
        let dark = RGBColor(rgb: 0x111019)
        let accent = RGBColor(rgb: 0x6FD8E8)
        #expect(accent.contrast(with: dark) >= 4.5)
        #expect(accent.readable(on: [dark]) == accent)
    }

    @Test func readableLiftsTowardWhiteUntilMinimumContrastIsMet() {
        let dark = RGBColor(rgb: 0x111019)
        let deepBlue = RGBColor(red: 0.05, green: 0.08, blue: 0.7)
        #expect(deepBlue.contrast(with: dark) < 4.5)

        let lifted = deepBlue.readable(on: [dark])
        #expect(lifted.contrast(with: dark) >= 4.5)
        #expect(lifted.luminance > deepBlue.luminance)
        // The lift keeps the hue direction: blue remains the strongest channel.
        #expect(lifted.blue > lifted.red)
        #expect(lifted.blue > lifted.green)

        let stricter = deepBlue.readable(on: [dark], minimum: 7)
        #expect(stricter.contrast(with: dark) >= 7)
        #expect(stricter.luminance > lifted.luminance)
    }

    @Test func readableDarkensTowardBlackOnLightSurfaces() {
        let light = RGBColor.white
        let yellow = RGBColor(rgb: 0xFFEE55)
        #expect(yellow.contrast(with: light) < 4.5)

        let darkened = yellow.readable(on: [light])
        #expect(darkened.contrast(with: light) >= 4.5)
        #expect(darkened.luminance < yellow.luminance)
        // Pulled toward black, not white: every channel shrinks and hue direction is kept.
        #expect(darkened.red < yellow.red)
        #expect(darkened.blue < yellow.blue)
        #expect(darkened.red > darkened.blue)

        let stricter = yellow.readable(on: [light], minimum: 7)
        #expect(stricter.contrast(with: light) >= 7)
        #expect(stricter.luminance < darkened.luminance)
    }

    @Test func readableOnLightSurfaceLeavesAlreadyReadableDarkColorAlone() {
        let navy = RGBColor(rgb: 0x1A237E)
        #expect(navy.contrast(with: .white) >= 4.5)
        #expect(navy.readable(on: [.white]) == navy)
    }

    @Test func readableSatisfiesMixedLightBackgrounds() {
        let backgrounds = [RGBColor.white, RGBColor(rgb: 0xEEEEF4), RGBColor(rgb: 0xDDDDE6)]
        let lifted = RGBColor(rgb: 0x6FD8E8).readable(on: backgrounds)
        for background in backgrounds {
            #expect(lifted.contrast(with: background) >= 4.5)
        }
        #expect(lifted.luminance < RGBColor(rgb: 0x6FD8E8).luminance)
    }

    @Test func readableFallsBackToBestNeutralWhenNoDirectionCanSatisfy() {
        // Neither black (2.0:1 on 0x404040) nor white (3.9:1 on 0x808080) reaches 4.5:1 against
        // both greys, so the neutral with the better worst case is returned.
        let midGrey = RGBColor(rgb: 0x808080)
        let impossible = [midGrey, RGBColor(rgb: 0x404040)]
        #expect(midGrey.readable(on: impossible) == .white)

        // When one direction can satisfy every background it is searched, not the endpoint.
        let solvable = [midGrey, RGBColor(rgb: 0xC0C0C0)]
        let result = midGrey.readable(on: solvable)
        #expect(result != .black)
        #expect(result.luminance < midGrey.luminance)
        for background in solvable {
            #expect(result.contrast(with: background) >= 4.5)
        }
    }

    @Test func readableWithNoBackgroundsReturnsSelf() {
        let color = RGBColor(rgb: 0x2070D8)
        #expect(color.readable(on: []) == color)
    }

    @Test func readableSatisfiesEveryBackground() {
        let backgrounds = [RGBColor(rgb: 0x111019), RGBColor(rgb: 0x303040), RGBColor(rgb: 0x404050)]
        let lifted = RGBColor(red: 0.6, green: 0.1, blue: 0.1).readable(on: backgrounds)
        for background in backgrounds {
            #expect(lifted.contrast(with: background) >= 4.5)
        }
    }

    @Test func onColorPicksHigherContrastNeutral() {
        #expect(RGBColor.white.onColor == .black)
        #expect(RGBColor.black.onColor == .white)
        #expect(RGBColor(rgb: 0x6FD8E8).onColor == .black)
        #expect(RGBColor(rgb: 0x2070D8).onColor == .white)
    }
}
