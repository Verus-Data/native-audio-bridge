// swift-tools-version:5.9
import PackageDescription

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
        .executableTarget(
            name: "NativeAudioBridgeTests",
            dependencies: ["NativeAudioBridgeLibrary"],
            path: "Sources/NativeAudioBridgeTests",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
