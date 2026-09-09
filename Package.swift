// swift-tools-version: 5.9
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "swift-palettecolor",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "PaletteColor", targets: ["PaletteColor"]),
    ],
    targets: [
        .target(
            name: "PaletteColor",
            path: "Sources/PaletteColor"
        ),
        .testTarget(
            name: "PaletteColorTests",
            dependencies: ["PaletteColor"],
            path: "Tests/PaletteColorTests"
        ),
    ]
)
