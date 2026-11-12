// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let artifactsRoot = packageRoot.appendingPathComponent("Artifacts")
let liteRtLmTag = "v0.19.1-3"

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
            checksum: "685ff2f959ed07d9753d5e1022770ff20c981c7acea42a9c27a43139e3e94e00"
        ),
        nativeRepoBinaryTarget(
            name: "CLiteRTLM",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-CLiteRTLM-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "c1573984374c7b56da1b9314f948d54300fb4b6e0988fd83f31fbd5101ace254"
        ),
        nativeRepoBinaryTarget(
            name: "CLiteRTLMMac",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-CLiteRTLMMac-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "cd06e43b5b08d436be076da25e5e14f354409d8d97f246009331b5e5546fbace"
        ),
        nativeRepoBinaryTarget(
            name: "LiteRt",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-LiteRt-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "254f07840b2c3dac8c575615086540f8fd6cd6174a395542379406012e58a42a"
        ),
        nativeRepoBinaryTarget(
            name: "LiteRtWebGpuAccelerator",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-LiteRtWebGpuAccelerator-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "88ec8b0531eab8267015f6821d7c8732ffa61b4fed9e7e220e1f31b751567b84"
        ),
        nativeRepoBinaryTarget(
            name: "WebgpuDawn",
            repository: "leehack/litert-lm-native",
            artifactName: "litert-lm-native-apple-WebgpuDawn-xcframework-\(liteRtLmTag).zip",
            tag: liteRtLmTag,
            checksum: "dda09bae837e3859497d643daa02ef6328374d1509b116ec60027111e909af31"
        ),
        .target(
            name: "llamadart_litert_lm_flutter",
            dependencies: [
                .target(name: "LiteRtLm", condition: .when(platforms: [.iOS, .macOS])),
                .target(name: "CLiteRTLM", condition: .when(platforms: [.iOS])),
                .target(name: "CLiteRTLMMac", condition: .when(platforms: [.macOS])),
                .target(name: "LiteRt", condition: .when(platforms: [.macOS])),
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
