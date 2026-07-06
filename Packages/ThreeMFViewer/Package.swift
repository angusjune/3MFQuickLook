// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreeMFViewer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ThreeMFViewer", targets: ["ThreeMFViewer"])
    ],
    dependencies: [
        .package(path: "../ThreeMFKit")
    ],
    targets: [
        .target(name: "ThreeMFViewer", dependencies: ["ThreeMFKit"]),
        .testTarget(name: "ThreeMFViewerTests", dependencies: ["ThreeMFViewer"]),
    ]
)
