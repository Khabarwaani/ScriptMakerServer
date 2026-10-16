// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentCoreBase",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "AgentCoreBase", targets: ["AgentCoreBase"])
    ],
    targets: [
        .target(
            name: "AgentCoreBase",
            path: "Sources/AgentCoreBase"
        ),
        .testTarget(
            name: "AgentCoreBaseTests",
            dependencies: ["AgentCoreBase"],
            path: "Tests/AgentCoreBaseTests"
        )
    ]
)
