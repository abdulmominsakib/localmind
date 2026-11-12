// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let artifactsRoot = packageRoot.appendingPathComponent("Artifacts")
let liteRtLmTag = "v0.18.1-4"

func localArtifactPath(_ name: String) -> String? {
    let path = artifactsRoot.appendingPathComponent(name).path
    return FileManager.default.fileExists(atPath: path) ? "Artifacts/\(name)" : nil
}

func nativeRepoBinaryTarget(
    name: String,
    repository: String,
    artifactName: String,
    tag: String,
    checksum: String
) -> Target {
    if let path = localArtifactPath("\(name).xcframework") {
        return .binaryTarget(name: name, path: path)
    }
    return .binaryTarget(
        name: name,
        url: "https://github.com/\(repository)/releases/download/\(tag)/\(artifactName)",
        checksum: checksum
    )
}

let package = Package(
    name: "llamadart_litert_lm_flutter",
    platforms: [
        .iOS("16.4"),
        .macOS("14.0")
    ],
    products: [
        .library(
            name: "llamadart-litert-lm-flutter",
            type: .dynamic,
            targets: ["llamadart_litert_lm_flutter"]
        )
    ],
    targets: [
        nativeRepoBinaryTarget(
            name: "LiteRtLm",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-LiteRtLm-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "1a8da5a59ceee358b38fe2c1553cbe47f4cdc64ba7a37d93054de34ecfc43cf1"
        ),
        nativeRepoBinaryTarget(
            name: "CLiteRTLM",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-CLiteRTLM-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "99605622d7a693a1e2f67b660aad0e11b517d83aa46c7e983a44c636d78ba170"
        ),
        nativeRepoBinaryTarget(
            name: "CLiteRTLMMac",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-CLiteRTLMMac-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "cb8170acba41790a97467fabfb0af61f75281c970f264ba529e01669fc3ee205"
        ),
        nativeRepoBinaryTarget(
            name: "LiteRtMetalAccelerator",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-LiteRtMetalAccelerator-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "40dea0c6c117e179190cac1ab960ba0adbeb536d66a40417073432d4f563ba53"
        ),
        nativeRepoBinaryTarget(
            name: "LiteRtTopKMetalSampler",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-LiteRtTopKMetalSampler-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "4a71e7d40cde518cdba9dec5d0d68010b2dd7de2862dd269e6898af5ea8de138"
        ),
        nativeRepoBinaryTarget(
            name: "LiteRt",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-LiteRt-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "eaa59c50ec8cde2b80e151630d6c07e24e6186bb3fad62d56de1967a24142b56"
        ),
        nativeRepoBinaryTarget(
            name: "LiteRtTopKWebGpuSampler",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-LiteRtTopKWebGpuSampler-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "af74411d48a53693722b78a3b92450ac71eca653f4123d3bc75b43781a4dcb93"
        ),
        nativeRepoBinaryTarget(
            name: "LiteRtWebGpuAccelerator",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-LiteRtWebGpuAccelerator-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "3aef75920e702ecbdf63afb5d3faa06ac5247207cf1759950ffb4d7f4e4fbb8c"
        ),
        nativeRepoBinaryTarget(
            name: "WebgpuDawn",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-WebgpuDawn-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "3fa0f576acd895eb5e8426c98b1da5e313057e9d57bb0f0a0c2b3eeefb33e3cd"
        ),
        .target(
            name: "llamadart_litert_lm_flutter",
            dependencies: [
                .target(name: "LiteRtLm", condition: .when(platforms: [.iOS, .macOS])),
                .target(name: "CLiteRTLM", condition: .when(platforms: [.iOS])),
                .target(name: "CLiteRTLMMac", condition: .when(platforms: [.macOS])),
                .target(name: "LiteRtMetalAccelerator", condition: .when(platforms: [.iOS])),
                .target(name: "LiteRtTopKMetalSampler", condition: .when(platforms: [.iOS])),
                .target(name: "LiteRt", condition: .when(platforms: [.macOS])),
                .target(name: "LiteRtTopKWebGpuSampler", condition: .when(platforms: [.macOS])),
                .target(name: "LiteRtWebGpuAccelerator", condition: .when(platforms: [.macOS])),
                .target(name: "WebgpuDawn", condition: .when(platforms: [.macOS]))
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-reexport_framework", "-Xlinker", "LiteRtLm"], .when(platforms: [.iOS])),
                .unsafeFlags(["-Xlinker", "-reexport_framework", "-Xlinker", "CLiteRTLM"], .when(platforms: [.iOS]))
            ]
        )
    ]
)
