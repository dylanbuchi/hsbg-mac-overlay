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
        // The overlay's own read-only reader of the game's memory (Mono metadata walk, names only).
        .target(
            name: "GameMemory"
        ),
        .executableTarget(
            name: "HSBGMacOverlay",
            dependencies: ["GameMemory"]
        ),
        .testTarget(
            name: "HSBGMacOverlayTests",
            dependencies: ["HSBGMacOverlay", "GameMemory"]
        )
    ]
)
