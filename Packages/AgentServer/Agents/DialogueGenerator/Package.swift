// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DialogueGenerator", platforms: [.macOS(.v14)],
    products: [.library(name: "DialogueGenerator", targets: ["DialogueGenerator"])],
    targets: [
        .target(name: "DialogueGenerator", path: ".", exclude: ["Tests", "README.md"],
                sources: ["Sources/DialogueGenerator/DialogueGenerator.swift"], resources: [.copy("1.0.0")]),
        .testTarget(name: "DialogueGeneratorTests", dependencies: ["DialogueGenerator"])
    ]
)
