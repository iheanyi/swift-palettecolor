// Ported from material-foundation/material-color-utilities' Java implementation
// (java/quantize/QuantizerWu.java) at commit 5b3618b16fdc3825e21d5679bafd144662088ea1, the
// copy Android vendors, rather than from the Swift port, which drifted from it. Java `int`
// arithmetic is reproduced with wrapping `Int32` operations, including the products that
// overflow on real artwork (the histogram's second moment, `variance`'s hypotenuse, and
// `maximize`'s numerators), so the boxes match Android's exactly. See NOTICE.
//
// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// An image quantizer that divides the RGB cube into boxes of minimal variance (Xiaolin Wu,
/// Graphics Gems II). Its colors seed `QuantizerWsmeans`, in the order it returns them.
struct QuantizerWu {
  private static let indexBits = 5
  private static let indexCount = 33  // (1 << indexBits) + 1
  private static let totalSize = 35937  // indexCount * indexCount * indexCount

  private var weights = [Int32](repeating: 0, count: totalSize)
  private var momentsR = [Int32](repeating: 0, count: totalSize)
  private var momentsG = [Int32](repeating: 0, count: totalSize)
  private var momentsB = [Int32](repeating: 0, count: totalSize)
  private var moments = [Double](repeating: 0, count: totalSize)
  private var cubes: [Box] = []

  /// Wu's colors in Java's order: each box's mean color, first occurrence kept. `histogram` is
  /// `QuantizerMap`'s result for the image (Java's Wu builds the same map itself).
  static func quantize(_ histogram: QuantizerResult, _ colorCount: Int) -> [Int] {
    var wu = QuantizerWu()
    wu.constructHistogram(histogram)
    wu.createMoments()
    let resultCount = wu.createBoxes(colorCount)
    var seen = Set<Int>()
    return wu.createResult(resultCount).filter { seen.insert($0).inserted }
  }

  static func index(_ r: Int, _ g: Int, _ b: Int) -> Int {
    (r << (indexBits * 2)) + (r << (indexBits + 1)) + r + (g << indexBits) + g + b
  }

  private mutating func constructHistogram(_ histogram: QuantizerResult) {
    let bitsToRemove = 8 - Self.indexBits
    for (pixel, population) in zip(histogram.colors, histogram.populations) {
      let red = (pixel >> 16) & 0xFF
      let green = (pixel >> 8) & 0xFF
      let blue = pixel & 0xFF
      let index = Self.index(
        (red >> bitsToRemove) + 1, (green >> bitsToRemove) + 1, (blue >> bitsToRemove) + 1)
      let count = Int32(truncatingIfNeeded: population)
      weights[index] &+= count
      momentsR[index] &+= Int32(red) &* count
      momentsG[index] &+= Int32(green) &* count
      momentsB[index] &+= Int32(blue) &* count
      // Java: `moments[index] += (count * ((red * red) + (green * green) + (blue * blue)))`, an
      // `int` product that wraps before it widens to `double`.
      moments[index] += Double(count &* Int32(red * red + green * green + blue * blue))
    }
  }

  private mutating func createMoments() {
    let n = Self.indexCount
    var area = [Int32](repeating: 0, count: n)
    var areaR = [Int32](repeating: 0, count: n)
    var areaG = [Int32](repeating: 0, count: n)
    var areaB = [Int32](repeating: 0, count: n)
    var area2 = [Double](repeating: 0, count: n)
    for r in 1..<n {
      for i in 0..<n {
        area[i] = 0
        areaR[i] = 0
        areaG[i] = 0
        areaB[i] = 0
        area2[i] = 0
      }
      for g in 1..<n {
        var line: Int32 = 0
        var lineR: Int32 = 0
        var lineG: Int32 = 0
        var lineB: Int32 = 0
        var line2 = 0.0
        for b in 1..<n {
          let index = Self.index(r, g, b)
          line &+= weights[index]
          lineR &+= momentsR[index]
          lineG &+= momentsG[index]
          lineB &+= momentsB[index]
          line2 += moments[index]

          area[b] &+= line
          areaR[b] &+= lineR
          areaG[b] &+= lineG
          areaB[b] &+= lineB
          area2[b] += line2

          let previousIndex = Self.index(r - 1, g, b)
          weights[index] = weights[previousIndex] &+ area[b]
          momentsR[index] = momentsR[previousIndex] &+ areaR[b]
          momentsG[index] = momentsG[previousIndex] &+ areaG[b]
          momentsB[index] = momentsB[previousIndex] &+ areaB[b]
          moments[index] = moments[previousIndex] + area2[b]
        }
      }
    }
  }

  private mutating func createBoxes(_ maxColorCount: Int) -> Int {
    guard maxColorCount > 0 else { return 0 }
    cubes = [Box](repeating: Box(), count: maxColorCount)
    var volumeVariance = [Double](repeating: 0, count: maxColorCount)
    cubes[0].r1 = Self.indexCount - 1
    cubes[0].g1 = Self.indexCount - 1
    cubes[0].b1 = Self.indexCount - 1

    var generatedColorCount = maxColorCount
    var next = 0
    // Java's `for (int i = 1; i < maxColorCount; i++)`, whose body may `i--` to retry a slot.
    var i = 1
    while i < maxColorCount {
      if cut(next, i) {
        volumeVariance[next] = cubes[next].vol > 1 ? variance(cubes[next]) : 0
        volumeVariance[i] = cubes[i].vol > 1 ? variance(cubes[i]) : 0
      } else {
        volumeVariance[next] = 0
        i -= 1
      }

      next = 0
      var temp = volumeVariance[0]
      var j = 1
      while j <= i {
        if volumeVariance[j] > temp {
          temp = volumeVariance[j]
          next = j
        }
        j += 1
      }
      if temp <= 0 {
        generatedColorCount = i + 1
        break
      }
      i += 1
    }
    return generatedColorCount
  }

  private func createResult(_ colorCount: Int) -> [Int] {
    var colors: [Int] = []
    for i in 0..<colorCount {
      let cube = cubes[i]
      let weight = volume(cube, weights)
      if weight > 0 {
        let r = Int(volume(cube, momentsR) / weight)
        let g = Int(volume(cube, momentsG) / weight)
        let b = Int(volume(cube, momentsB) / weight)
        colors.append((255 << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF))
      }
    }
    return colors
  }

  private func variance(_ cube: Box) -> Double {
    let dr = volume(cube, momentsR)
    let dg = volume(cube, momentsG)
    let db = volume(cube, momentsB)
    let xx =
      moments[Self.index(cube.r1, cube.g1, cube.b1)]
      - moments[Self.index(cube.r1, cube.g1, cube.b0)]
      - moments[Self.index(cube.r1, cube.g0, cube.b1)]
      + moments[Self.index(cube.r1, cube.g0, cube.b0)]
      - moments[Self.index(cube.r0, cube.g1, cube.b1)]
      + moments[Self.index(cube.r0, cube.g1, cube.b0)]
      + moments[Self.index(cube.r0, cube.g0, cube.b1)]
      - moments[Self.index(cube.r0, cube.g0, cube.b0)]
    // Java: `int hypotenuse = dr * dr + dg * dg + db * db;` wraps; the division is `double`.
    let hypotenuse = dr &* dr &+ dg &* dg &+ db &* db
    let volume = volume(cube, weights)
    return xx - Double(hypotenuse) / Double(volume)
  }

  private mutating func cut(_ oneIndex: Int, _ twoIndex: Int) -> Bool {
    var one = cubes[oneIndex]
    var two = cubes[twoIndex]
    let wholeR = volume(one, momentsR)
    let wholeG = volume(one, momentsG)
    let wholeB = volume(one, momentsB)
    let wholeW = volume(one, weights)

    let maxRResult = maximize(one, .red, one.r0 + 1, one.r1, wholeR, wholeG, wholeB, wholeW)
    let maxGResult = maximize(one, .green, one.g0 + 1, one.g1, wholeR, wholeG, wholeB, wholeW)
    let maxBResult = maximize(one, .blue, one.b0 + 1, one.b1, wholeR, wholeG, wholeB, wholeW)

    let cutDirection: Direction
    let maxR = maxRResult.maximum
    let maxG = maxGResult.maximum
    let maxB = maxBResult.maximum
    if maxR >= maxG && maxR >= maxB {
      if maxRResult.cutLocation < 0 {
        return false
      }
      cutDirection = .red
    } else if maxG >= maxR && maxG >= maxB {
      cutDirection = .green
    } else {
      cutDirection = .blue
    }

    two.r1 = one.r1
    two.g1 = one.g1
    two.b1 = one.b1

    switch cutDirection {
    case .red:
      one.r1 = maxRResult.cutLocation
      two.r0 = one.r1
      two.g0 = one.g0
      two.b0 = one.b0
    case .green:
      one.g1 = maxGResult.cutLocation
      two.r0 = one.r0
      two.g0 = one.g1
      two.b0 = one.b0
    case .blue:
      one.b1 = maxBResult.cutLocation
      two.r0 = one.r0
      two.g0 = one.g0
      two.b0 = one.b1
    }

    one.vol = (one.r1 - one.r0) * (one.g1 - one.g0) * (one.b1 - one.b0)
    two.vol = (two.r1 - two.r0) * (two.g1 - two.g0) * (two.b1 - two.b0)
    cubes[oneIndex] = one
    cubes[twoIndex] = two
    return true
  }

  private func maximize(
    _ cube: Box, _ direction: Direction, _ first: Int, _ last: Int,
    _ wholeR: Int32, _ wholeG: Int32, _ wholeB: Int32, _ wholeW: Int32
  ) -> (cutLocation: Int, maximum: Double) {
    let bottomR = bottom(cube, direction, momentsR)
    let bottomG = bottom(cube, direction, momentsG)
    let bottomB = bottom(cube, direction, momentsB)
    let bottomW = bottom(cube, direction, weights)

    var max = 0.0
    var cut = -1
    var i = first
    while i < last {
      defer { i += 1 }
      var halfR = bottomR &+ top(cube, direction, i, momentsR)
      var halfG = bottomG &+ top(cube, direction, i, momentsG)
      var halfB = bottomB &+ top(cube, direction, i, momentsB)
      var halfW = bottomW &+ top(cube, direction, i, weights)
      if halfW == 0 {
        continue
      }
      // Java: `double tempNumerator = halfR * halfR + halfG * halfG + halfB * halfB;`, an `int`
      // expression that wraps before it widens.
      var temp = Double(halfR &* halfR &+ halfG &* halfG &+ halfB &* halfB) / Double(halfW)

      halfR = wholeR &- halfR
      halfG = wholeG &- halfG
      halfB = wholeB &- halfB
      halfW = wholeW &- halfW
      if halfW == 0 {
        continue
      }
      temp += Double(halfR &* halfR &+ halfG &* halfG &+ halfB &* halfB) / Double(halfW)

      if temp > max {
        max = temp
        cut = i
      }
    }
    return (cut, max)
  }

  private func volume(_ cube: Box, _ moment: [Int32]) -> Int32 {
    moment[Self.index(cube.r1, cube.g1, cube.b1)]
      &- moment[Self.index(cube.r1, cube.g1, cube.b0)]
      &- moment[Self.index(cube.r1, cube.g0, cube.b1)]
      &+ moment[Self.index(cube.r1, cube.g0, cube.b0)]
      &- moment[Self.index(cube.r0, cube.g1, cube.b1)]
      &+ moment[Self.index(cube.r0, cube.g1, cube.b0)]
      &+ moment[Self.index(cube.r0, cube.g0, cube.b1)]
      &- moment[Self.index(cube.r0, cube.g0, cube.b0)]
  }

  private func bottom(_ cube: Box, _ direction: Direction, _ moment: [Int32]) -> Int32 {
    switch direction {
    case .red:
      return 0 &- moment[Self.index(cube.r0, cube.g1, cube.b1)]
        &+ moment[Self.index(cube.r0, cube.g1, cube.b0)]
        &+ moment[Self.index(cube.r0, cube.g0, cube.b1)]
        &- moment[Self.index(cube.r0, cube.g0, cube.b0)]
    case .green:
      return 0 &- moment[Self.index(cube.r1, cube.g0, cube.b1)]
        &+ moment[Self.index(cube.r1, cube.g0, cube.b0)]
        &+ moment[Self.index(cube.r0, cube.g0, cube.b1)]
        &- moment[Self.index(cube.r0, cube.g0, cube.b0)]
    case .blue:
      return 0 &- moment[Self.index(cube.r1, cube.g1, cube.b0)]
        &+ moment[Self.index(cube.r1, cube.g0, cube.b0)]
        &+ moment[Self.index(cube.r0, cube.g1, cube.b0)]
        &- moment[Self.index(cube.r0, cube.g0, cube.b0)]
    }
  }

  private func top(_ cube: Box, _ direction: Direction, _ position: Int, _ moment: [Int32]) -> Int32 {
    switch direction {
    case .red:
      return moment[Self.index(position, cube.g1, cube.b1)]
        &- moment[Self.index(position, cube.g1, cube.b0)]
        &- moment[Self.index(position, cube.g0, cube.b1)]
        &+ moment[Self.index(position, cube.g0, cube.b0)]
    case .green:
      return moment[Self.index(cube.r1, position, cube.b1)]
        &- moment[Self.index(cube.r1, position, cube.b0)]
        &- moment[Self.index(cube.r0, position, cube.b1)]
        &+ moment[Self.index(cube.r0, position, cube.b0)]
    case .blue:
      return moment[Self.index(cube.r1, cube.g1, position)]
        &- moment[Self.index(cube.r1, cube.g0, position)]
        &- moment[Self.index(cube.r0, cube.g1, position)]
        &+ moment[Self.index(cube.r0, cube.g0, position)]
    }
  }

  private enum Direction {
    case red, green, blue
  }

  private struct Box {
    var r0 = 0
    var r1 = 0
    var g0 = 0
    var g1 = 0
    var b0 = 0
    var b1 = 0
    var vol = 0
  }
}
