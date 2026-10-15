// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShekharJokeGenerator",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ShekharJokeGenerator", targets: ["ShekharJokeGenerator"])],
    dependencies: [
        .package(path: "../../../AgentCoreBase"),
        .package(path: "../../../NewsAgent")
    ],
    targets: [
        .target(
            name: "ShekharJokeGenerator",
            dependencies: [
                .product(name: "AgentCoreBase", package: "AgentCoreBase"),
                .product(name: "NewsAgent", package: "NewsAgent")
            ],
            path: ".",
            exclude: ["Tests", "README.md"],
            sources: ["Sources/ShekharJokeGenerator/ShekharJokeGenerator.swift"],
            resources: [.copy("1.0.0")]
        ),
        .testTarget(
            name: "ShekharJokeGeneratorTests",
            dependencies: [
                "ShekharJokeGenerator",
                .product(name: "AgentCoreBase", package: "AgentCoreBase"),
                .product(name: "NewsAgent", package: "NewsAgent")
            ]
        )
    ]
)
