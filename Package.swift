// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HSBGMacOverlay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "HSBGMacOverlay",
            targets: ["HSBGMacOverlay"]
        )
    ],
    targets: [
        // Read-only reader for the leaderboard tribe counts, through HearthMirror's own Mono reader.
        .target(
            name: "TribeMemory"
        ),
        .executableTarget(
            name: "HSBGMacOverlay",
            dependencies: ["TribeMemory"]
        ),
        .testTarget(
            name: "HSBGMacOverlayTests",
            dependencies: ["HSBGMacOverlay"]
        )
    ],
    cxxLanguageStandard: .cxx17
)
