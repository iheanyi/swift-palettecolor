// Ported from material-foundation/material-color-utilities' Java implementation
// (java/quantize/QuantizerCelebi.java) at commit 5b3618b16fdc3825e21d5679bafd144662088ea1, the
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

/// Wu's boxes as the starting clusters of Wsmeans, as Android's `QuantizerCelebi` does. The pixel
/// histogram is built once and shared (Java builds the same first-seen map in both passes).
enum QuantizerCelebi {
  static func quantize(_ pixels: [Int], _ maxColors: Int) -> QuantizerResult {
    let histogram = QuantizerMap.quantize(pixels)
    let wuClusters = QuantizerWu.quantize(histogram, maxColors)
    return QuantizerWsmeans.quantize(histogram, startingClusters: wuClusters, maxColors: maxColors)
  }
}
