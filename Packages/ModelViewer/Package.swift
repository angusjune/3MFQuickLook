// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModelViewer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ModelViewer", targets: ["ModelViewer"])
    ],
    dependencies: [
        .package(path: "../ThreeMFKit"),
        .package(path: "../GLBKit"),
    ],
    targets: [
        .target(name: "ModelViewer", dependencies: ["ThreeMFKit", "GLBKit"]),
        .testTarget(name: "ModelViewerTests", dependencies: ["ModelViewer"]),
    ]
)
