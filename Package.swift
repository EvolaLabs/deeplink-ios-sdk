// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DeepLinkingSDK",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "DeepLinkingSDK",
            targets: ["DeepLinkingSDK"]
        ),
    ],
    dependencies: [
        // No external dependencies to keep it lightweight
    ],
    targets: [
        .target(
            name: "DeepLinkingSDK",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
