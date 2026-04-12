// swift-tools-version:5.9
import PackageDescription

// Semantic version — update via semantic-release on merge to main
let currentVersion = "0.1.0"

let package = Package(
    name: "NativeAudioBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NativeAudioBridge", targets: ["NativeAudioBridge"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NativeAudioBridgeLibrary",
            path: "Sources/NativeAudioBridge"
        ),
        .executableTarget(
            name: "NativeAudioBridge",
            dependencies: ["NativeAudioBridgeLibrary"],
            path: "Sources/NativeAudioBridgeApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "NativeAudioBridgeTests",
            dependencies: ["NativeAudioBridgeLibrary"],
            path: "Sources/NativeAudioBridgeTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
