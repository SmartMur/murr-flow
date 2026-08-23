// swift-tools-version: 6.2
import Foundation
import PackageDescription

// FluidAudio's ASR implementation requires Apple Silicon. Release builds set this to
// zero for the Intel slice, which still ships Apple's native transcription engine.
let parakeetEnabled = ProcessInfo.processInfo.environment["MURR_FLOW_ENABLE_PARAKEET"] != "0"

let packageDependencies: [Package.Dependency] = parakeetEnabled
    ? [.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")]
    : []

let appDependencies: [Target.Dependency] = ["MurrFlowDictionary"] + (parakeetEnabled
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
            path: "Sources/MurmurDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "MurrFlow",
            dependencies: appDependencies,
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
