// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NativeAudioBridge",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NativeAudioBridgeLibrary",
            dependencies: [],
            path: "Sources/NativeAudioBridge",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "NativeAudioBridge",
            dependencies: ["NativeAudioBridgeLibrary"],
            path: "Sources/NativeAudioBridgeApp"
        ),
        .testTarget(
            name: "NativeAudioBridgeTests",
            dependencies: ["NativeAudioBridgeLibrary"],
            path: "Tests/NativeAudioBridgeTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)