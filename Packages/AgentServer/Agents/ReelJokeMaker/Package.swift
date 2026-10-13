// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReelJokeMaker",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ReelJokeMaker", targets: ["ReelJokeMaker"])],
    targets: [
        .target(
            name: "ReelJokeMaker",
            path: ".",
            exclude: ["Tests", "README.md"],
            sources: ["Sources/ReelJokeMaker/ReelJokeMaker.swift"],
            resources: [.copy("1.0.0")]
        ),
        .testTarget(name: "ReelJokeMakerTests", dependencies: ["ReelJokeMaker"])
    ]
)
