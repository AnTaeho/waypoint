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
        // 원격 설정 도우미(scripts/remote-setup.sh)가 쓰는 설치기 명령행(TRK-53)
        .executable(name: "waypoint-integration", targets: ["waypoint-integration"]),
    ],
    targets: [
        .target(
            name: "WaypointKit",
            path: "Shared"
        ),
        .executableTarget(
            name: "waypoint-integration",
            dependencies: ["WaypointKit"],
            path: "Tools/waypoint-integration"
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
