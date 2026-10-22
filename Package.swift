// swift-tools-version: 6.2
import PackageDescription

// O app é só interface: todo o domínio (dados, regras, IA, CLI e servidor MCP) vive no Core Rust (crates/),
// empacotado junto do app por scripts/build-app.sh. O app fala com ele por MCP (stdio), local ou por SSH.
let package = Package(
    name: "VibeDeck",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "VibeDeckApp", targets: ["VibeDeckApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
        // 1.12+ ships a Metal shader, which needs the separately downloaded Metal Toolchain to build.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.11.0")),
    ],
    targets: [
        .executableTarget(
            name: "VibeDeckApp",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            resources: [.copy("GraphResources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VibeDeckAppTests",
            dependencies: ["VibeDeckApp", .product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
