// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NewsResearcher",
    platforms: [.macOS("27.0")],
    products: [.library(name: "NewsResearcher", targets: ["NewsResearcher"])],
    dependencies: [
        .package(path: "../../../AgentCoreBase"),
        .package(url: "https://github.com/Khabarwaani/KhabarwaaniAgent", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "NewsResearcher",
            dependencies: [
                .product(name: "AgentCoreBase", package: "AgentCoreBase"),
                .product(name: "KhabarwaaniAgent", package: "KhabarwaaniAgent")
            ],
            path: ".",
            exclude: ["Tests", "README.md"],
            sources: ["Sources/NewsResearcher/NewsResearcher.swift"],
            resources: [.copy("1.1.0")]
        ),
        .testTarget(
            name: "NewsResearcherTests",
            dependencies: [
                "NewsResearcher",
                .product(name: "AgentCoreBase", package: "AgentCoreBase"),
                .product(name: "KhabarwaaniAgent", package: "KhabarwaaniAgent")
            ]
        )
    ]
)
