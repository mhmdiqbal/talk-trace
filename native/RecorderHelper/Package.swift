// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RecorderHelper",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "RecorderHelper",
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
