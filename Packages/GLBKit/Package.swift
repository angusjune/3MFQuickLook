// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GLBKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GLBKit", targets: ["GLBKit"])
    ],
    targets: [
        .target(name: "GLBKit"),
        .testTarget(name: "GLBKitTests", dependencies: ["GLBKit"]),
    ]
)
