// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreeMFKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ThreeMFKit", targets: ["ThreeMFKit"])
    ],
    targets: [
        .target(name: "ThreeMFKit"),
        .testTarget(name: "ThreeMFKitTests", dependencies: ["ThreeMFKit"]),
    ]
)
