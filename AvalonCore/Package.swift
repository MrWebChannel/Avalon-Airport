// swift-tools-version: 5.9
// Avalon Airport core: domain model v0.3, governance engine, plugins, .avj manifests.
// One third-party dependency: Yams, for reading and writing YAML (.avj files, flight plans).

import PackageDescription

let package = Package(
    name: "AvalonCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AvalonCore", targets: ["AvalonCore"]),
        .executable(name: "avalon-demo", targets: ["avalon-demo"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(name: "AvalonCore", dependencies: ["Yams"]),
        .executableTarget(name: "avalon-demo", dependencies: ["AvalonCore"]),
        .testTarget(name: "AvalonCoreTests", dependencies: ["AvalonCore"])
    ]
)
