// PaletteColor
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PaletteColor

final class RGBColorTests: XCTestCase {
    func testLuminanceAndContrastMatchWCAG() {
        XCTAssertEqual(RGBColor.white.luminance, 1, accuracy: 1e-9)
        XCTAssertEqual(RGBColor.black.luminance, 0, accuracy: 1e-9)
        XCTAssertEqual(RGBColor.white.contrast(with: .black), 21, accuracy: 1e-9)
        XCTAssertEqual(RGBColor.black.contrast(with: .white), 21, accuracy: 1e-9)
        XCTAssertEqual(RGBColor.white.contrast(with: .white), 1, accuracy: 1e-9)

        // #767676 on white is the canonical ~4.54:1 WCAG AA boundary grey.
        let grey = RGBColor(rgb: 0x767676)
        XCTAssertEqual(grey.contrast(with: .white), 4.54, accuracy: 0.01)
    }

    func testPackedRGBRoundTrips() {
        let color = RGBColor(rgb: 0x2070D8)
        XCTAssertEqual(color.red, Double(0x20) / 255)
        XCTAssertEqual(color.green, Double(0x70) / 255)
        XCTAssertEqual(color.blue, Double(0xD8) / 255)
        XCTAssertEqual(color.rgb, 0x2070D8)
        XCTAssertEqual(RGBColor(red8: 17, green8: 16, blue8: 25).rgb, 0x111019)
        XCTAssertEqual(RGBColor(rgb: 0xFF2070D8).rgb, 0x2070D8)
    }

    func testMixedInterpolatesAndClampsFraction() {
        let mid = RGBColor.black.mixed(with: .white, fraction: 0.5)
        XCTAssertEqual(mid, RGBColor(red: 0.5, green: 0.5, blue: 0.5))
        XCTAssertEqual(RGBColor.black.mixed(with: .white, fraction: 2), .white)
        XCTAssertEqual(RGBColor.black.mixed(with: .white, fraction: -1), .black)
    }

    func testChromaIsZeroForGreys() {
        XCTAssertEqual(RGBColor(red: 0.3, green: 0.3, blue: 0.3).chroma, 0)
        XCTAssertEqual(RGBColor(red: 1, green: 0, blue: 0).chroma, 1)
    }

    func testReadableReturnsSelfWhenAlreadyLighterAndContrasting() {
        let dark = RGBColor(rgb: 0x111019)
        let accent = RGBColor(rgb: 0x6FD8E8)
        XCTAssertGreaterThanOrEqual(accent.contrast(with: dark), 4.5)
        XCTAssertEqual(accent.readable(on: [dark]), accent)
    }

    func testReadableLiftsTowardWhiteUntilMinimumContrastIsMet() {
        let dark = RGBColor(rgb: 0x111019)
        let deepBlue = RGBColor(red: 0.05, green: 0.08, blue: 0.7)
        XCTAssertLessThan(deepBlue.contrast(with: dark), 4.5)

        let lifted = deepBlue.readable(on: [dark])
        XCTAssertGreaterThanOrEqual(lifted.contrast(with: dark), 4.5)
        XCTAssertGreaterThan(lifted.luminance, deepBlue.luminance)
        // The lift keeps the hue direction: blue remains the strongest channel.
        XCTAssertGreaterThan(lifted.blue, lifted.red)
        XCTAssertGreaterThan(lifted.blue, lifted.green)

        let stricter = deepBlue.readable(on: [dark], minimum: 7)
        XCTAssertGreaterThanOrEqual(stricter.contrast(with: dark), 7)
        XCTAssertGreaterThan(stricter.luminance, lifted.luminance)
    }

    func testReadableDarkensTowardBlackOnLightSurfaces() {
        let light = RGBColor.white
        let yellow = RGBColor(rgb: 0xFFEE55)
        XCTAssertLessThan(yellow.contrast(with: light), 4.5)

        let darkened = yellow.readable(on: [light])
        XCTAssertGreaterThanOrEqual(darkened.contrast(with: light), 4.5)
        XCTAssertLessThan(darkened.luminance, yellow.luminance)
        // Pulled toward black, not white: every channel shrinks and hue direction is kept.
        XCTAssertLessThan(darkened.red, yellow.red)
        XCTAssertLessThan(darkened.blue, yellow.blue)
        XCTAssertGreaterThan(darkened.red, darkened.blue)

        let stricter = yellow.readable(on: [light], minimum: 7)
        XCTAssertGreaterThanOrEqual(stricter.contrast(with: light), 7)
        XCTAssertLessThan(stricter.luminance, darkened.luminance)
    }

    func testReadableOnLightSurfaceLeavesAlreadyReadableDarkColorAlone() {
        let navy = RGBColor(rgb: 0x1A237E)
        XCTAssertGreaterThanOrEqual(navy.contrast(with: .white), 4.5)
        XCTAssertEqual(navy.readable(on: [.white]), navy)
    }

    func testReadableSatisfiesMixedLightBackgrounds() {
        let backgrounds = [RGBColor.white, RGBColor(rgb: 0xEEEEF4), RGBColor(rgb: 0xDDDDE6)]
        let lifted = RGBColor(rgb: 0x6FD8E8).readable(on: backgrounds)
        for background in backgrounds {
            XCTAssertGreaterThanOrEqual(lifted.contrast(with: background), 4.5)
        }
        XCTAssertLessThan(lifted.luminance, RGBColor(rgb: 0x6FD8E8).luminance)
    }

    func testReadableFallsBackToBestNeutralWhenNoDirectionCanSatisfy() {
        // Neither black (2.0:1 on 0x404040) nor white (3.9:1 on 0x808080) reaches 4.5:1 against
        // both greys, so the neutral with the better worst case is returned.
        let midGrey = RGBColor(rgb: 0x808080)
        let impossible = [midGrey, RGBColor(rgb: 0x404040)]
        XCTAssertEqual(midGrey.readable(on: impossible), .white)

        // When one direction can satisfy every background it is searched, not the endpoint.
        let solvable = [midGrey, RGBColor(rgb: 0xC0C0C0)]
        let result = midGrey.readable(on: solvable)
        XCTAssertNotEqual(result, .black)
        XCTAssertLessThan(result.luminance, midGrey.luminance)
        for background in solvable {
            XCTAssertGreaterThanOrEqual(result.contrast(with: background), 4.5)
        }
    }

    func testReadableWithNoBackgroundsReturnsSelf() {
        let color = RGBColor(rgb: 0x2070D8)
        XCTAssertEqual(color.readable(on: []), color)
    }

    func testReadableSatisfiesEveryBackground() {
        let backgrounds = [RGBColor(rgb: 0x111019), RGBColor(rgb: 0x303040), RGBColor(rgb: 0x404050)]
        let lifted = RGBColor(red: 0.6, green: 0.1, blue: 0.1).readable(on: backgrounds)
        for background in backgrounds {
            XCTAssertGreaterThanOrEqual(lifted.contrast(with: background), 4.5)
        }
    }

    func testOnColorPicksHigherContrastNeutral() {
        XCTAssertEqual(RGBColor.white.onColor, .black)
        XCTAssertEqual(RGBColor.black.onColor, .white)
        XCTAssertEqual(RGBColor(rgb: 0x6FD8E8).onColor, .black)
        XCTAssertEqual(RGBColor(rgb: 0x2070D8).onColor, .white)
    }
}
