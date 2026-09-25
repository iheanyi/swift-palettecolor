// PaletteColor
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import PaletteColor

/// The seed pipeline against Material Color Utilities' Java implementation, the copy Android
/// vendors (`QuantizerCelebi.quantize(pixels, clamp(n / 16, 5, 128))`, then
/// `Score.score(…, 4, 0xFF1B6EF3, false)`). Every expected value below was produced by that Java
/// code (JDK `java.util.Random`, the same algorithm as Android's libcore) on the same pixels.
@Suite("Material Color Utilities parity with Android's Java")
struct MaterialColorUtilitiesParityTests {
    static let googleBlue = 0xFF1B_6EF3

    // MARK: java.util.Random

    /// `new Random(0x42688)`, then twelve `nextInt(bound)` calls, per bound.
    static let javaRandomSequences: [(bound: Int32, sequence: [Int32])] = [
        (5, [1, 3, 0, 0, 1, 1, 0, 4, 0, 3, 1, 1]),
        (7, [5, 1, 1, 2, 0, 1, 3, 4, 1, 3, 1, 0]),
        (16, [6, 13, 4, 10, 1, 3, 11, 13, 1, 1, 14, 3]),
        (40, [1, 38, 0, 5, 21, 31, 30, 9, 15, 38, 1, 16]),
        (128, [49, 111, 34, 84, 13, 30, 91, 105, 9, 12, 118, 24]),
        (1, [Int32](repeating: 0, count: 12)),
    ]

    @Test("JavaRandom matches java.util.Random seeded like Wsmeans", arguments: javaRandomSequences)
    func javaRandom(bound: Int32, sequence: [Int32]) {
        var random = JavaRandom(seed: 0x42688)
        #expect((0..<12).map { _ in random.nextInt(bound) } == sequence)
    }

    @Test func javaRandomReachesTheWholeRange() {
        // The generator this replaced returned values below 2^63, so `Int.random(in:using:)` only
        // ever produced the lower half of a range and the centroid picker spun forever.
        var random = JavaRandom(seed: 0x42688)
        #expect(Set((0..<20_000).map { _ in random.nextInt(40) }) == Set(0..<40))
    }

    // MARK: Termination

    @Test func wsmeansNeverAsksForMoreClustersThanWuStartedWith() {
        // Forty distinct colors, two starting clusters: the old port needed 38 extra random
        // centroids from a generator that could reach 20 of them, and never returned.
        let pixels = (0..<40).map { 0xFF00_0000 | ($0 * 6) << 16 | 0x4080 }
        let result = QuantizerWsmeans.quantize(
            QuantizerMap.quantize(pixels), startingClusters: [0xFF00_4080, 0xFFEA_4080], maxColors: 128)
        #expect(result.colors.count <= 2)
        #expect(result.populations.reduce(0, +) == 40)
    }

    @Test func aGrayRampThatUsedToSpinForeverQuantizesLikeJava() {
        let ranked = Self.seed(Self.image(112, 112) { x, _ in
            let v = UInt32(x * 255 / 111)
            return v << 16 | v << 8 | v
        })
        #expect(ranked.clusterCount == 23)
        #expect(ranked.score == [0xFFF6_F6F6])
    }

    // MARK: Goldens

    struct ClusterCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let pixels: [UInt32]
        let colors: [Int]
        let populations: [Int]

        init(_ name: String, _ pixels: [UInt32], _ clusters: KeyValuePairs<Int, Int>) {
            testDescription = name
            self.pixels = pixels
            colors = clusters.map(\.key)
            populations = clusters.map(\.value)
        }
    }

    @Test("Clusters match Java in order", arguments: [
        // `count * (r² + g² + b²)` overflows Java's `int` in Wu's histogram here.
        ClusterCase("solid white", image(112, 112) { _, _ in 0xFFFFFF }, [0xFFFF_FFFF: 12544]),
        ClusterCase("black and white halves", image(112, 112) { x, _ in x < 56 ? 0x000000 : 0xFFFFFF },
                    [0xFF77_7777: 12544]),
        ClusterCase("lime 60 / pink 15 / gray 25", image(112, 112) { x, y in
            let i = y * 112 + x
            return i < 7526 ? 0x9CCC32 : (i < 9408 ? 0xE91E63 : 0x303030)
        }, [0xFF91_9040: 12544]),
        ClusterCase("a red dot on white", image(112, 112) { x, y in
            (x - 56) * (x - 56) + (y - 56) * (y - 56) < 100 ? 0xD62828 : 0xFFFFFF
        }, [0xFFD6_2828: 305, 0xFFFF_FFFF: 12239]),
        ClusterCase("two-color 50x20", image(50, 20) { x, y in (x + y) % 3 == 0 ? 0xF4A261 : 0x264653 },
                    [0xFF26_4653: 667, 0xFFF4_A261: 333]),
        ClusterCase("one pixel", image(1, 1) { _, _ in 0x3366CC }, [0xFF33_66CC: 1]),
        ClusterCase("5-level poster", poster(5), [
            0xFF00_0040: 529, 0xFFFF_0040: 506, 0xFF2A_7F40: 1035, 0xFF00_FF40: 506,
            0xFFFF_FF40: 484, 0xFF95_A941: 1519, 0xFFEA_9441: 1496, 0xFFA1_FF40: 990,
            0xFF7F_0040: 529, 0xFFFF_3F40: 484, 0xFF3F_FF40: 484, 0xFFBF_2A40: 990,
            0xFF3F_3F40: 484, 0xFF2B_BF40: 990, 0xFF7F_3F40: 506, 0xFF3F_0040: 506,
            0xFF00_3F40: 506,
        ]),
    ])
    func clustersMatchJavaInOrder(_ testCase: ClusterCase) {
        let quantized = QuantizerCelebi.quantize(testCase.pixels.map(MediaArtworkScheme.argb(fromRGB:)),
                                                 MediaArtworkScheme.maxColors(forArea: testCase.pixels.count))
        #expect(quantized.colors == testCase.colors)
        #expect(quantized.populations == testCase.populations)
    }

    struct RankedCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let pixels: [UInt32]
        let clusterCount: Int
        let score: [Int]
    }

    @Test("Ranked seeds match Java", arguments: [
        RankedCase(testDescription: "40-level poster", pixels: poster(40), clusterCount: 128,
                   score: [0xFF1E_F740, 0xFFF5_0D40, 0xFFA2_7E40, 0xFF11_0B40]),
        RankedCase(testDescription: "13-color palette", pixels: palette(seed: 3), clusterCount: 7,
                   score: [0xFF55_0AF8, 0xFFE5_6FE1, 0xFF58_BD82, 0xFFC1_4229]),
    ])
    func rankedSeedsMatchJava(_ testCase: RankedCase) throws {
        let ranked = Self.seed(testCase.pixels)
        #expect(ranked.clusterCount == testCase.clusterCount)
        #expect(ranked.score == testCase.score)
        let top = try #require(testCase.score.first)
        #expect(MediaArtworkScheme.seedColor(pixels: testCase.pixels).rgb == UInt32(top & 0xFF_FFFF))
    }

    // MARK: Fixtures (the same generators produced the Java reference values)

    static func seed(_ pixels: [UInt32]) -> (clusterCount: Int, score: [Int]) {
        let quantized = QuantizerCelebi.quantize(pixels.map(MediaArtworkScheme.argb(fromRGB:)),
                                                 MediaArtworkScheme.maxColors(forArea: pixels.count))
        return (quantized.colors.count,
                Score.score(quantized, desired: 4, fallbackColorARGB: googleBlue, filter: false))
    }

    static func image(_ width: Int, _ height: Int, _ pixel: (Int, Int) -> UInt32) -> [UInt32] {
        var pixels: [UInt32] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(pixel(x, y) & 0xFF_FFFF)
            }
        }
        return pixels
    }

    static func poster(_ levels: Int) -> [UInt32] {
        image(112, 112) { x, y in
            let r = UInt32((x * levels / 112) * 255 / max(levels - 1, 1))
            let g = UInt32((y * levels / 112) * 255 / max(levels - 1, 1))
            return r << 16 | g << 8 | 0x40
        }
    }

    /// The harness's 64-bit LCG (PCG's multiplier and increment), high 31 bits per step.
    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt32 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt32(truncatingIfNeeded: state >> 33)
        }
    }

    static func palette(seed: UInt64) -> [UInt32] {
        var colors = LCG(state: seed &* 31)
        let palette = (0..<(Int(seed) * 3 + 4)).map { _ in colors.next() }
        var picks = LCG(state: seed &* 97)
        return image(112, 112) { _, _ in palette[Int(picks.next()) % palette.count] }
    }
}
