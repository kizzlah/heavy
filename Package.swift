// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "heavy",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "HeavyCore",
            targets: ["HeavyCore"]
        ),
        .executable(
            name: "heavy",
            targets: ["heavy"]
        ),
    ],
    targets: [
        .target(
            name: "HeavyCore",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .executableTarget(
            name: "heavy",
            dependencies: ["HeavyCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "HeavyCoreTests",
            dependencies: ["HeavyCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
