// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TalkTraceHelper",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "TalkTraceHelper",
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
