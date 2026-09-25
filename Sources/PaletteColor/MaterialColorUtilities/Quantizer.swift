// Ported from material-foundation/material-color-utilities' Java implementation
// (java/quantize/QuantizerResult.java) at commit 5b3618b16fdc3825e21d5679bafd144662088ea1, the
// copy Android vendors, rather than from the Swift port, which drifted from it. See NOTICE.
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

/// Colors and their populations in the order Java's `LinkedHashMap` yields them. The order is
/// part of the result: Wu's order seeds Wsmeans, and Wsmeans' order breaks `Score` ties, exactly
/// as on Android. A Swift `Dictionary` would reorder them on every launch.
struct QuantizerResult: Equatable {
  var colors: [Int] = []
  var populations: [Int] = []

  var colorToCount: [Int: Int] {
    Dictionary(zip(colors, populations), uniquingKeysWith: { first, _ in first })
  }
}

/// `java.util.Random`, bit for bit: the 48-bit linear congruential generator and the documented
/// `nextInt(bound)` algorithm that Android's `QuantizerWsmeans` seeds with `0x42688`.
struct JavaRandom {
  private static let multiplier: Int64 = 0x5_DEEC_E66D
  private static let mask: Int64 = (1 << 48) - 1
  private var seed: Int64

  init(seed: Int64) {
    self.seed = (seed ^ Self.multiplier) & Self.mask
  }

  mutating func next(_ bits: Int) -> Int32 {
    seed = (seed &* Self.multiplier &+ 0xB) & Self.mask
    return Int32(truncatingIfNeeded: seed >> (48 - bits))
  }

  mutating func nextInt(_ bound: Int32) -> Int32 {
    precondition(bound > 0, "bound must be positive")
    var r = next(31)
    let m = bound &- 1
    if bound & m == 0 {
      return Int32(truncatingIfNeeded: (Int64(bound) &* Int64(r)) >> 31)
    }
    var u = r
    r = u % bound
    while u &- r &+ m < 0 {
      u = next(31)
      r = u % bound
    }
    return r
  }
}
