// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TypeStats",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TypeStats", targets: ["TypeStats"]),
    ],
    targets: [
        // Counting model, per-app/day aggregation and the SwiftData store.
        // No event tap here, so all counting logic is testable.
        .target(name: "TypeStatsCore"),
        // Menu bar app: event tap, popup UI and test seams.
        .executableTarget(name: "TypeStats", dependencies: ["TypeStatsCore"]),
        .testTarget(name: "TypeStatsCoreTests", dependencies: ["TypeStatsCore"]),
    ]
)
