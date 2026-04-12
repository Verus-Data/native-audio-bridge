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
            path: "Sources/NativeAudioBridge"
        ),
        .testTarget(
            name: "NativeAudioBridgeTests",
            dependencies: ["NativeAudioBridgeLibrary"],
            path: "Tests/NativeAudioBridgeTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)