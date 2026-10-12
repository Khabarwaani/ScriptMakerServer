// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScriptWriter",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ScriptWriter", targets: ["ScriptWriter"])],
    targets: [
        .target(name: "ScriptWriter", path: ".", exclude: ["Tests", "README.md"],
                sources: ["Sources/ScriptWriter/ScriptWriter.swift"], resources: [.copy("1.0.0")]),
        .testTarget(name: "ScriptWriterTests", dependencies: ["ScriptWriter"])
    ]
)
