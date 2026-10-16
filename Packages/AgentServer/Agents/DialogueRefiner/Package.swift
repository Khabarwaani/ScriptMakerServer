// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DialogueRefiner", platforms: [.macOS("27.0")],
    products: [.library(name: "DialogueRefiner", targets: ["DialogueRefiner"])],
    targets: [
        .target(name: "DialogueRefiner", path: ".", exclude: ["Tests", "README.md"],
                sources: ["Sources/DialogueRefiner/DialogueRefiner.swift"], resources: [.copy("1.0.0")]),
        .testTarget(name: "DialogueRefinerTests", dependencies: ["DialogueRefiner"])
    ]
)
