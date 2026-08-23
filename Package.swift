// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MurrFlow",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Parakeet via CoreML on the Neural Engine. Optional at runtime — Apple's
        // SpeechTranscriber is the default engine and needs no dependency at all.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")
    ],
    targets: [
        // The dictionary is its own target so it can be tested directly.
        .target(
            name: "MurrFlowDictionary",
            path: "Sources/MurmurDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "MurrFlow",
            dependencies: [
                "MurrFlowDictionary",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/MurmurYouTube",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "MurrFlowDictionaryTests",
            dependencies: ["MurrFlowDictionary"],
            path: "Tests/MurmurDictionaryTests",
            resources: [.copy("dictionary-test-vectors.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
