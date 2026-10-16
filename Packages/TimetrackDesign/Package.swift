// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TimetrackDesign",
    defaultLocalization: "de",
    platforms: [.macOS(.v27), .iOS(.v27), .watchOS(.v27)],
    products: [
        .library(name: "TimetrackDesign", targets: ["TimetrackDesign"]),
    ],
    dependencies: [
        .package(path: "../TimetrackCore"),
    ],
    targets: [
        .target(name: "TimetrackDesign", dependencies: [.product(name: "TimetrackCore", package: "TimetrackCore")]),
        .testTarget(name: "TimetrackDesignTests", dependencies: ["TimetrackDesign"]),
    ]
)
