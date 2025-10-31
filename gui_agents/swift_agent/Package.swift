// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentS3Swift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "agent-s3",
            targets: ["AgentS3Swift"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AgentS3Swift",
            dependencies: [],
            path: "Sources/AgentS3Swift"
        ),
    ]
)
