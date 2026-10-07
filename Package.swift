// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VibeDeck",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "VibeDeckApp", targets: ["VibeDeckApp"]),
        .executable(name: "vibedeck", targets: ["vibedeck"]),
        .library(name: "VibeDeckCore", targets: ["VibeDeckCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
    ],
    targets: [
        .target(name: "VibeDeckCore"),
        .executableTarget(
            name: "VibeDeckApp",
            dependencies: [
                "VibeDeckCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        .executableTarget(
            name: "vibedeck",
            dependencies: [
                "VibeDeckCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(name: "VibeDeckCoreTests", dependencies: ["VibeDeckCore"]),
    ]
)
