// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HostAppKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HostAppKit", targets: ["HostAppKit"])
    ],
    dependencies: [
        // The library itself is parser-agnostic; only the tests parse the
        // bundled sample to prove it is a valid 3MF.
        .package(path: "../ThreeMFKit")
    ],
    targets: [
        .target(
            name: "HostAppKit",
            resources: [.copy("Resources/SampleGem.3mf")]),
        .testTarget(
            name: "HostAppKitTests",
            dependencies: ["HostAppKit", "ThreeMFKit"]),
    ]
)
