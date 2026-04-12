// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NativeAudioBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NativeAudioBridge", targets: ["NativeAudioBridge"]),
        .executable(name: "NativeAudioBridgeTests", targets: ["NativeAudioBridgeTests"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NativeAudioBridgeLibrary",
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
        .executableTarget(
            name: "NativeAudioBridgeTests",
            dependencies: ["NativeAudioBridgeLibrary"],
            path: "Tests/NativeAudioBridgeTests",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)