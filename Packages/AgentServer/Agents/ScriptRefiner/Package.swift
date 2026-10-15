// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ScriptRefiner", platforms: [.macOS(.v14)],
    products: [.library(name: "ScriptRefiner", targets: ["ScriptRefiner"])],
    targets: [
        .target(name: "ScriptRefiner", path: ".", exclude: ["Tests", "README.md"],
                sources: ["Sources/ScriptRefiner/ScriptRefiner.swift"], resources: [.copy("1.1.0"), .copy("1.2.0")]),
        .testTarget(name: "ScriptRefinerTests", dependencies: ["ScriptRefiner"])
    ]
)
