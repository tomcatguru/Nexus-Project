// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NexusGantt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NexusGantt", targets: ["NexusGantt"])
    ],
    targets: [
        .target(name: "NexusCore"),
        .executableTarget(name: "NexusGantt", dependencies: ["NexusCore"]),
        .testTarget(name: "NexusCoreTests", dependencies: ["NexusCore"])
    ]
)
