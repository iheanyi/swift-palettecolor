// Vendored from material-foundation/material-color-utilities (swift/Sources/MaterialColorUtilities)
// at commit 5b3618b16fdc3825e21d5679bafd144662088ea1. Local changes: access control reduced to
// internal; see NOTICE for the full list. Do not edit without updating NOTICE.
//
// Copyright 2023 Google LLC
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

class QuantizerMap: Quantizer {
  func quantize(
    _ pixels: [Int], _ maxColors: Int, returnInputPixelToClusterPixel: Bool = false
  )
    -> QuantizerResult
  {
    var countByColor: [Int: Int] = [:]
    for pixel in pixels {
      let alpha = ColorUtils.alphaFromArgb(pixel)
      if alpha < 255 {
        continue
      }
      countByColor[pixel] = (countByColor[pixel] ?? 0) + 1
    }
    return QuantizerResult(countByColor)
  }
}
