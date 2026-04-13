// swift-tools-version:5.9
import PackageDescription

// Semantic version — updated by semantic-release on merge to main
let currentVersion = "0.1.0"

let package = Package(
    name: "NativeAudioBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NativeAudioBridge", targets: ["NativeAudioBridge"]),
        .executable(name: "NativeAudioBridgeTestRunner", targets: ["NativeAudioBridgeTestRunner"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "NativeAudioBridgeLibrary",
            path: "Sources/NativeAudioBridge"
        ),
        .executableTarget(
            name: "NativeAudioBridge",
            dependencies: [
                "NativeAudioBridgeLibrary",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/NativeAudioBridgeApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "NativeAudioBridgeTestRunner",
            dependencies: ["NativeAudioBridgeLibrary"],
            path: "Sources/NativeAudioBridgeTests",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)