// PaletteColor
// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 the swift-palettecolor authors. Licensed under the Apache License, Version 2.0.
//
// Derived from AndroidX Palette's ColorCutQuantizer.java (Apache License 2.0),
// Copyright 2018 The Android Open Source Project, androidx-main at
// 81432a7d3a860faea8b18fb2a4712f1d6420f705. See NOTICE for details.

import Foundation

/// Median-cut quantizer over a 5-bit-per-channel (RGB555) histogram, matching AndroidX
/// `ColorCutQuantizer` bit for bit so both platforms produce the same swatches.
enum ColorCutQuantizer {
    enum Component { case red, green, blue }

    private static let quantizeWordWidth = 5
    private static let mask = (1 << quantizeWordWidth) - 1
    private static let histogramSize = 1 << (quantizeWordWidth * 3)

    static func quantize(pixels: [UInt32], maxColors: Int, filter: Palette.Filter) -> [Palette.Swatch] {
        var histogram = [Int](repeating: 0, count: histogramSize)
        for pixel in pixels {
            let red = quantizeChannel(Int((pixel >> 16) & 0xff))
            let green = quantizeChannel(Int((pixel >> 8) & 0xff))
            let blue = quantizeChannel(Int(pixel & 0xff))
            histogram[red << (quantizeWordWidth * 2) | green << quantizeWordWidth | blue] += 1
        }

        var distinct = [Int]()
        for color in histogram.indices where histogram[color] > 0 {
            let rgb = approximate(color)
            if !filter.allows(rgb: rgb, hsl: HSL(rgb: rgb)) { histogram[color] = 0 }
            if histogram[color] > 0 { distinct.append(color) }
        }

        guard !distinct.isEmpty else { return [] }
        if distinct.count <= maxColors {
            return distinct.map { color in
                Palette.Swatch(rgb: approximate(color), population: histogram[color])
            }
        }

        var colors = distinct
        var boxes = [Box(lower: 0, upper: colors.count - 1, colors: colors, histogram: histogram)]
        while boxes.count < maxColors {
            guard let index = boxes.indices.max(by: { boxes[$0].volume < boxes[$1].volume }) else { break }
            var box = boxes.remove(at: index)
            guard box.canSplit else { boxes.append(box); break }
            let newBox = box.split(colors: &colors, histogram: histogram)
            // AndroidX offers the split box first and then the remainder back to its priority queue.
            boxes.append(newBox)
            boxes.append(box)
        }

        return boxes.map { box in box.averageColor(colors: colors, histogram: histogram) }
            .filter { swatch in filter.allows(rgb: swatch.rgb, hsl: swatch.hsl) }
    }

    // MARK: - Channel packing

    /// 8-bit channel to 5-bit (`modifyWordWidth(value, 8, 5)`).
    static func quantizeChannel(_ channel: Int) -> Int { channel >> 3 }
    /// 5-bit channel back to 8-bit (`modifyWordWidth(value, 5, 8)`).
    static func approximateChannel(_ channel: Int) -> Int { (channel << 3) & 0xff }

    static func red(_ color: Int) -> Int { (color >> (quantizeWordWidth * 2)) & mask }
    static func green(_ color: Int) -> Int { (color >> quantizeWordWidth) & mask }
    static func blue(_ color: Int) -> Int { color & mask }

    static func swapSignificantOctet(_ color: Int, dimension: Component) -> Int {
        switch dimension {
        case .red: return color
        case .green:
            return green(color) << (quantizeWordWidth * 2) | red(color) << quantizeWordWidth | blue(color)
        case .blue:
            return blue(color) << (quantizeWordWidth * 2) | green(color) << quantizeWordWidth | red(color)
        }
    }

    static func approximate(_ color: Int) -> UInt32 {
        UInt32(approximateChannel(red(color)) << 16
            | approximateChannel(green(color)) << 8
            | approximateChannel(blue(color)))
    }

    static func approximate(red: Int, green: Int, blue: Int) -> UInt32 {
        UInt32(approximateChannel(red) << 16
            | approximateChannel(green) << 8
            | approximateChannel(blue))
    }

    // MARK: - Vbox

    struct Box {
        var lower: Int
        var upper: Int
        private(set) var population = 0
        private(set) var minimumRed = 0
        private(set) var maximumRed = 0
        private(set) var minimumGreen = 0
        private(set) var maximumGreen = 0
        private(set) var minimumBlue = 0
        private(set) var maximumBlue = 0

        init(lower: Int, upper: Int, colors: [Int], histogram: [Int]) {
            self.lower = lower
            self.upper = upper
            fit(colors: colors, histogram: histogram)
        }

        var volume: Int {
            (maximumRed - minimumRed + 1)
                * (maximumGreen - minimumGreen + 1)
                * (maximumBlue - minimumBlue + 1)
        }

        var canSplit: Bool { upper > lower }

        mutating func split(colors: inout [Int], histogram: [Int]) -> Box {
            precondition(canSplit, "Cannot split a box with only 1 color")
            let splitPoint = findSplitPoint(colors: &colors, histogram: histogram)
            let newBox = Box(lower: splitPoint + 1, upper: upper, colors: colors, histogram: histogram)
            upper = splitPoint
            fit(colors: colors, histogram: histogram)
            return newBox
        }

        func averageColor(colors: [Int], histogram: [Int]) -> Palette.Swatch {
            var redSum = 0
            var greenSum = 0
            var blueSum = 0
            var totalPopulation = 0
            for index in lower...upper {
                let color = colors[index]
                let count = histogram[color]
                totalPopulation += count
                redSum += count * ColorCutQuantizer.red(color)
                greenSum += count * ColorCutQuantizer.green(color)
                blueSum += count * ColorCutQuantizer.blue(color)
            }
            // Math.round(float) semantics: floor(x + 0.5) in single precision.
            let red = Int(floor(Float(redSum) / Float(totalPopulation) + 0.5))
            let green = Int(floor(Float(greenSum) / Float(totalPopulation) + 0.5))
            let blue = Int(floor(Float(blueSum) / Float(totalPopulation) + 0.5))
            return Palette.Swatch(
                rgb: ColorCutQuantizer.approximate(red: red, green: green, blue: blue),
                population: totalPopulation
            )
        }

        private mutating func fit(colors: [Int], histogram: [Int]) {
            var minRed = Int.max
            var minGreen = Int.max
            var minBlue = Int.max
            var maxRed = Int.min
            var maxGreen = Int.min
            var maxBlue = Int.min
            var count = 0
            for index in lower...upper {
                let color = colors[index]
                count += histogram[color]
                let red = ColorCutQuantizer.red(color)
                let green = ColorCutQuantizer.green(color)
                let blue = ColorCutQuantizer.blue(color)
                minRed = min(minRed, red); maxRed = max(maxRed, red)
                minGreen = min(minGreen, green); maxGreen = max(maxGreen, green)
                minBlue = min(minBlue, blue); maxBlue = max(maxBlue, blue)
            }
            population = count
            minimumRed = minRed; maximumRed = maxRed
            minimumGreen = minGreen; maximumGreen = maxGreen
            minimumBlue = minBlue; maximumBlue = maxBlue
        }

        private func longestDimension() -> Component {
            let redLength = maximumRed - minimumRed
            let greenLength = maximumGreen - minimumGreen
            let blueLength = maximumBlue - minimumBlue
            if redLength >= greenLength && redLength >= blueLength { return .red }
            if greenLength >= redLength && greenLength >= blueLength { return .green }
            return .blue
        }

        private func findSplitPoint(colors: inout [Int], histogram: [Int]) -> Int {
            let dimension = longestDimension()
            var sorted = Array(colors[lower...upper])
            if dimension != .red {
                sorted = sorted.map { ColorCutQuantizer.swapSignificantOctet($0, dimension: dimension) }
            }
            sorted.sort()
            if dimension != .red {
                sorted = sorted.map { ColorCutQuantizer.swapSignificantOctet($0, dimension: dimension) }
            }
            for (offset, color) in sorted.enumerated() {
                colors[lower + offset] = color
            }

            let midpoint = population / 2
            var count = 0
            for index in lower...upper {
                count += histogram[colors[index]]
                if count >= midpoint { return min(upper - 1, index) }
            }
            return lower
        }
    }
}
