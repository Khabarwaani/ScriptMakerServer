// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NewsAgent",
    platforms: [.macOS(.v14), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "NewsAgent", targets: ["NewsAgent"])
    ],
    dependencies: [
        .package(path: "../AgentAtom")
    ],
    targets: [
        .target(
            name: "NewsAgent",
            dependencies: [
                .product(name: "AgentAtom", package: "AgentAtom")
            ]
        ),
        .testTarget(
            name: "NewsAgentTests",
            dependencies: [
                "NewsAgent",
                .product(name: "AgentAtom", package: "AgentAtom")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
