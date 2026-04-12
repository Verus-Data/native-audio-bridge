// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NativeAudioBridge",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "NativeAudioBridge",
            dependencies: [],
            path: "Sources/NativeAudioBridge",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)