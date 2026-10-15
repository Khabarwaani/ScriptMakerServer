// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReelIdeaGenerator", platforms: [.macOS(.v14)],
    products: [.library(name: "ReelIdeaGenerator", targets: ["ReelIdeaGenerator"])],
    targets: [
        .target(name: "ReelIdeaGenerator", path: ".", exclude: ["Tests", "README.md"],
                sources: ["Sources/ReelIdeaGenerator/ReelIdeaGenerator.swift"], resources: [.copy("1.0.0")]),
        .testTarget(name: "ReelIdeaGeneratorTests", dependencies: ["ReelIdeaGenerator"])
    ]
)
