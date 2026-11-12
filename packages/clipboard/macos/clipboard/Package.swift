// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "clipboard",
    platforms: [
        .macOS(.v10_14),
    ],
    products: [
        .library(
            name: "clipboard",
            targets: ["clipboard"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "clipboard",
            dependencies: [],
            path: "Sources/clipboard"
        ),
    ]
)

