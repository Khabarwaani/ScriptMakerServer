// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreeSceneStoryCreator",
    platforms: [.macOS("27.0")],
    products: [.library(name: "ThreeSceneStoryCreator", targets: ["ThreeSceneStoryCreator"])],
    dependencies: [
        .package(path: "../../../AgentCoreBase"),
        .package(url: "https://github.com/Khabarwaani/KhabarwaaniAgent", exact: "0.3.2")
    ],
    targets: [
        .target(
            name: "ThreeSceneStoryCreator",
            dependencies: [
                .product(name: "AgentCoreBase", package: "AgentCoreBase"),
                .product(name: "KhabarwaaniAgent", package: "KhabarwaaniAgent")
            ],
            path: ".",
            exclude: ["Tests", "README.md"],
            sources: ["Sources/ThreeSceneStoryCreator/ThreeSceneStoryCreator.swift"],
            resources: [.copy("2.0.0")]
        ),
        .testTarget(
            name: "ThreeSceneStoryCreatorTests",
            dependencies: [
                "ThreeSceneStoryCreator",
                .product(name: "AgentCoreBase", package: "AgentCoreBase"),
                .product(name: "KhabarwaaniAgent", package: "KhabarwaaniAgent")
            ]
        )
    ]
)
