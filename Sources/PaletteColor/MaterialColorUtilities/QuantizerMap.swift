// Ported from material-foundation/material-color-utilities' Java implementation
// (java/quantize/QuantizerMap.java) at commit 5b3618b16fdc3825e21d5679bafd144662088ea1, the
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

/// Distinct pixels in first-seen order with their counts (Java's `LinkedHashMap`). Every pixel
/// counts, whatever its alpha, as in Java.
enum QuantizerMap {
  static func quantize(_ pixels: [Int]) -> QuantizerResult {
    var slots: [Int: Int] = [:]
    slots.reserveCapacity(min(pixels.count, 1 << 14))
    var result = QuantizerResult()
    for pixel in pixels {
      if let slot = slots[pixel] {
        result.populations[slot] += 1
      } else {
        slots[pixel] = result.colors.count
        result.colors.append(pixel)
        result.populations.append(1)
      }
    }
    return result
  }
}
