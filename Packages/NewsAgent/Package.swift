// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NewsAgent",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "NewsAgent", targets: ["NewsAgent"])
    ],
    dependencies: [
        .package(url: "https://github.com/abhi266raj/AgentAtom", exact: "0.1.0")
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
