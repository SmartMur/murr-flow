// swift-tools-version: 6.2
import Foundation
import PackageDescription

// FluidAudio's ASR implementation requires Apple Silicon. Release builds set this to
// zero for the Intel slice, which still ships Apple's native transcription engine.
let parakeetEnabled = ProcessInfo.processInfo.environment["MURR_FLOW_ENABLE_PARAKEET"] != "0"

let packageDependencies: [Package.Dependency] = parakeetEnabled
    ? [.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")]
    : []

let appDependencies: [Target.Dependency] = ["MurrFlowDictionary", "MurrFlowTranscript"] + (parakeetEnabled
    ? [.product(name: "FluidAudio", package: "FluidAudio")]
    : [])

let package = Package(
    name: "MurrFlow",
    platforms: [.macOS(.v26)],
    dependencies: packageDependencies,
    targets: [
        // The dictionary is its own target so it can be tested directly.
        .target(
            name: "MurrFlowDictionary",
            path: "Sources/MurrFlowDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Segment stitching lives outside the executable so it can be tested. An
        // executableTarget cannot be imported by a test target, and the behaviour that
        // broke — pauses, task rotation, out-of-order finals — is exactly what needs
        // regression cover.
        .target(
            name: "MurrFlowTranscript",
            path: "Sources/MurrFlowTranscript",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "MurrFlow",
            dependencies: appDependencies,
            path: "Sources/MurrFlow",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "MurrFlowTranscriptTests",
            dependencies: ["MurrFlowTranscript"],
            path: "Tests/MurrFlowTranscriptTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MurrFlowDictionaryTests",
            dependencies: ["MurrFlowDictionary"],
            path: "Tests/MurrFlowDictionaryTests",
            resources: [.copy("dictionary-test-vectors.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
