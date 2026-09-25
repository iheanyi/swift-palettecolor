// Ported from material-foundation/material-color-utilities' Java implementation
// (java/quantize/QuantizerWsmeans.java) at commit 5b3618b16fdc3825e21d5679bafd144662088ea1, the
// copy Android vendors, rather than from the Swift port, which drifted from it: the Swift port
// picked extra random centroids with a generator that reaches only half of any range, so
// `while indices.contains(index)` never ended for artwork whose Wu pass returned fewer than
// `min(maxColors, distinct colors)` clusters. Java clamps the cluster count to the starting
// clusters and never seeds extra ones. See NOTICE.
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

/// Weighted square means (M. Emre Celebi, "Improving the Performance of K-Means for Color
/// Quantization", 2011), K-means over deduplicated pixels in L*a*b* with a triangle-inequality
/// skip. Every loop is bounded: at most `maxIterations` passes over the points and clusters.
enum QuantizerWsmeans {
  private static let maxIterations = 10
  private static let minMovementDistance = 3.0

  /// - Parameters:
  ///   - histogram: the image's distinct pixels in first-seen order (`QuantizerMap`), the order
  ///     Java's `LinkedHashMap` gives them.
  ///   - startingClusters: Wu's colors, in Wu's order.
  static func quantize(
    _ histogram: QuantizerResult, startingClusters: [Int], maxColors: Int
  ) -> QuantizerResult {
    let pointCount = histogram.colors.count
    var clusterCount = min(maxColors, pointCount)
    if !startingClusters.isEmpty {
      clusterCount = min(clusterCount, startingClusters.count)
    }
    guard clusterCount > 0 else { return QuantizerResult() }
    let k = clusterCount

    var points = [Double](repeating: 0, count: pointCount * 3)
    for i in 0..<pointCount {
      let lab = ColorUtils.labFromArgb(histogram.colors[i])
      points[i * 3] = lab[0]
      points[i * 3 + 1] = lab[1]
      points[i * 3 + 2] = lab[2]
    }
    let counts = histogram.populations

    var clusters = [Double](repeating: 0, count: k * 3)
    let seeded = min(startingClusters.count, k)
    for i in 0..<seeded {
      let lab = ColorUtils.labFromArgb(startingClusters[i])
      clusters[i * 3] = lab[0]
      clusters[i * 3 + 1] = lab[1]
      clusters[i * 3 + 2] = lab[2]
    }
    // Java leaves these clusters null (and would throw); only a caller without Wu reaches them.
    for i in seeded..<k {
      clusters[i * 3] = points[i * 3]
      clusters[i * 3 + 1] = points[i * 3 + 1]
      clusters[i * 3 + 2] = points[i * 3 + 2]
    }

    var random = JavaRandom(seed: 0x42688)
    var clusterIndices = [Int](repeating: 0, count: pointCount)
    for i in 0..<pointCount {
      clusterIndices[i] = Int(random.nextInt(Int32(k)))
    }

    // Java's `distanceToIndexMatrix`, reduced to what it observably does. Each row holds the
    // distances from one cluster, sorted ascending in place every pass. Java writes each pair into
    // row slots by position and then sorts, so a slot's value survives from the previous pass when
    // nothing overwrites it (the diagonal starts at Java's `-1`). The assignment step compares
    // `row[previous][j]` (a sorted distance) with `clusters[j]` (an unsorted cluster), an upstream
    // quirk kept for parity. Java's parallel `indexMatrix` is never read, so it is not kept.
    var rows = [Double](repeating: -1, count: k * k)
    var pixelCountSums = [Int](repeating: 0, count: k)
    var sumA = [Double](repeating: 0, count: k)
    var sumB = [Double](repeating: 0, count: k)
    var sumC = [Double](repeating: 0, count: k)

    // The passes below use `while` counters over raw pointers: a Debug build compiles this package
    // without optimization, where `for i in 0..<n` goes through the generic `IndexingIterator` on
    // every step and made one cover take seconds.
    var iteration = 0
    while iteration < maxIterations {
      defer { iteration += 1 }
      clusters.withUnsafeBufferPointer { c in
        rows.withUnsafeMutableBufferPointer { r in
          var i = 0
          while i < k {
            var j = i + 1
            while j < k {
              let distance = labDistance(c, i, c, j)
              r[j * k + i] = distance
              r[i * k + j] = distance
              j += 1
            }
            var row = UnsafeMutableBufferPointer(rebasing: r[(i * k)..<((i + 1) * k)])
            row.sort()
            i += 1
          }
        }
      }

      var pointsMoved = 0
      points.withUnsafeBufferPointer { pointBuffer in
        clusters.withUnsafeBufferPointer { clusterBuffer in
          rows.withUnsafeBufferPointer { rowBuffer in
            clusterIndices.withUnsafeMutableBufferPointer { assignedBuffer in
              guard let p = pointBuffer.baseAddress, let c = clusterBuffer.baseAddress,
                    let r = rowBuffer.baseAddress, let assigned = assignedBuffer.baseAddress else { return }
              var i = 0
              while i < pointCount {
                let pL = p[i * 3], pA = p[i * 3 + 1], pB = p[i * 3 + 2]
                let previousClusterIndex = assigned[i]
                let previous = previousClusterIndex * 3
                let previousL = pL - c[previous], previousA = pA - c[previous + 1], previousB = pB - c[previous + 2]
                let previousDistance = previousL * previousL + previousA * previousA + previousB * previousB
                let limit = 4 * previousDistance
                let row = previousClusterIndex * k
                var minimumDistance = previousDistance
                var newClusterIndex = -1
                var j = 0
                while j < k {
                  if r[row + j] < limit {
                    let cluster = j * 3
                    let dL = pL - c[cluster], dA = pA - c[cluster + 1], dB = pB - c[cluster + 2]
                    let distance = dL * dL + dA * dA + dB * dB
                    if distance < minimumDistance {
                      minimumDistance = distance
                      newClusterIndex = j
                    }
                  }
                  j += 1
                }
                if newClusterIndex != -1 {
                  let distanceChange = abs(minimumDistance.squareRoot() - previousDistance.squareRoot())
                  if distanceChange > minMovementDistance {
                    pointsMoved += 1
                    assigned[i] = newClusterIndex
                  }
                }
                i += 1
              }
            }
          }
        }
      }

      if pointsMoved == 0 && iteration != 0 {
        break
      }

      var i = 0
      while i < k {
        pixelCountSums[i] = 0
        sumA[i] = 0
        sumB[i] = 0
        sumC[i] = 0
        i += 1
      }
      i = 0
      while i < pointCount {
        let clusterIndex = clusterIndices[i]
        let count = counts[i]
        let weight = Double(count)
        pixelCountSums[clusterIndex] += count
        let a: Double = points[i * 3] * weight
        let b: Double = points[i * 3 + 1] * weight
        let c: Double = points[i * 3 + 2] * weight
        sumA[clusterIndex] += a
        sumB[clusterIndex] += b
        sumC[clusterIndex] += c
        i += 1
      }
      i = 0
      while i < k {
        let count = pixelCountSums[i]
        if count == 0 {
          clusters[i * 3] = 0
          clusters[i * 3 + 1] = 0
          clusters[i * 3 + 2] = 0
        } else {
          clusters[i * 3] = sumA[i] / Double(count)
          clusters[i * 3 + 1] = sumB[i] / Double(count)
          clusters[i * 3 + 2] = sumC[i] / Double(count)
        }
        i += 1
      }
    }

    var result = QuantizerResult()
    var seen = Set<Int>()
    for i in 0..<k {
      let count = pixelCountSums[i]
      if count == 0 {
        continue
      }
      let argb = ColorUtils.argbFromLab(clusters[i * 3], clusters[i * 3 + 1], clusters[i * 3 + 2])
      if !seen.insert(argb).inserted {
        continue
      }
      result.colors.append(argb)
      result.populations.append(count)
    }
    return result
  }

  /// `PointProviderLab.distance`: squared Euclidean distance, summed L, a, b in that order.
  @inline(__always)
  private static func labDistance(
    _ one: UnsafeBufferPointer<Double>, _ i: Int, _ two: UnsafeBufferPointer<Double>, _ j: Int
  ) -> Double {
    let dL = one[i * 3] - two[j * 3]
    let dA = one[i * 3 + 1] - two[j * 3 + 1]
    let dB = one[i * 3 + 2] - two[j * 3 + 2]
    return dL * dL + dA * dA + dB * dB
  }
}
