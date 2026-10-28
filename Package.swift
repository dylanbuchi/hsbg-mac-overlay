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
        .executableTarget(
            name: "HSBGMacOverlay"
        ),
        .testTarget(
            name: "HSBGMacOverlayTests",
            dependencies: ["HSBGMacOverlay"]
        )
    ]
)

