// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TimetrackCore",
    defaultLocalization: "de",
    platforms: [.macOS(.v27), .iOS(.v27), .watchOS(.v27)],
    products: [
        .library(name: "TimetrackCore", targets: ["TimetrackCore"]),
        .library(name: "TimetrackStores", targets: ["TimetrackStores"]),
    ],
    targets: [
        .target(name: "TimetrackCore", resources: [.process("Resources")]),
        .target(name: "TimetrackStores", dependencies: ["TimetrackCore"]),
        .testTarget(name: "TimetrackCoreTests", dependencies: ["TimetrackCore", "TimetrackStores"]),
    ]
)
