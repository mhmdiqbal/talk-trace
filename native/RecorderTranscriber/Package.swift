// swift-tools-version:6.0
import PackageDescription

// whisper.cpp is built by scripts/build-whisper.sh into native/vendor, which is
// gitignored. Both paths are derived here so nothing is hardcoded per machine.
let vendor = "\(Context.packageDirectory)/../vendor/whisper"
let build = "\(vendor)/build"

let headerFlags = [
    "-I\(vendor)/include",
    "-I\(vendor)/ggml/include",
]

let package = Package(
    name: "RecorderTranscriber",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(headerFlags)]
        ),
        .executableTarget(
            name: "RecorderTranscriber",
            dependencies: ["CWhisper"],
            path: "Sources/RecorderTranscriber",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(headerFlags.flatMap { ["-Xcc", $0] }),
            ],
            linkerSettings: [
                // Static archives, so consumers come before providers.
                .unsafeFlags([
                    "-L\(build)/src",
                    "-L\(build)/ggml/src",
                    "-L\(build)/ggml/src/ggml-metal",
                    "-L\(build)/ggml/src/ggml-blas",
                    "-lwhisper",
                    "-lggml",
                    "-lggml-cpu",
                    "-lggml-metal",
                    "-lggml-blas",
                    "-lggml-base",
                    "-lc++",
                ]),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
    ]
)
