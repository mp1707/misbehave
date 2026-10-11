// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MisbehaveKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MisbehaveKit", targets: ["MisbehaveKit"]),
    ],
    targets: [
        .target(name: "MisbehaveKit", resources: [.process("Resources")]),
        .testTarget(name: "MisbehaveKitTests", dependencies: ["MisbehaveKit"]),
    ]
)
