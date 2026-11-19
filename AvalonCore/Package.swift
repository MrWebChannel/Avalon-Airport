// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AvalonCore",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AvalonCore", targets: ["AvalonCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0")
    ],
    targets: [
        .target(name: "AvalonCore", dependencies: ["Yams"]),
        .testTarget(name: "AvalonCoreTests", dependencies: ["AvalonCore"])
    ]
)
