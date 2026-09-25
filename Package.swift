// swift-tools-version: 6.0
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
    dependencies: [
        // Development only: `swift package plugin swiftlint`. No target depends on it, so SwiftPM's
        // target-based resolution never fetches it for packages that depend on PaletteColor.
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.65.1"),
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
