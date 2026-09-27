// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WaypointKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "WaypointKit", targets: ["WaypointKit"]),
    ],
    targets: [
        .target(
            name: "WaypointKit",
            path: "Shared"
        ),
        .testTarget(
            name: "WaypointKitTests",
            dependencies: ["WaypointKit"],
            path: "Tests",
            sources: ["WaypointKitTests"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
