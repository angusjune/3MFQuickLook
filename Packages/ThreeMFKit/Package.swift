// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreeMFKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ThreeMFKit", targets: ["ThreeMFKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.19"))
    ],
    targets: [
        .target(name: "ThreeMFKit", dependencies: ["ZIPFoundation"]),
        .testTarget(name: "ThreeMFKitTests", dependencies: ["ThreeMFKit"]),
        // Measures parse time and peak memory at the parse seam; the recorded
        // numbers live in docs/perf-baseline.md.
        .executableTarget(name: "threemf-bench", dependencies: ["ThreeMFKit"]),
    ]
)
