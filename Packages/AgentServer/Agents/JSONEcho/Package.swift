// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JSONEcho",
    platforms: [.macOS(.v14)],
    products: [.library(name: "JSONEcho", targets: ["JSONEcho"])],
    targets: [
        .target(name: "JSONEcho", path: ".", exclude: ["Tests", "README.md"],
                sources: ["Sources/JSONEcho/JSONEcho.swift"], resources: [.copy("1.0.0")]),
        .testTarget(name: "JSONEchoTests", dependencies: ["JSONEcho"])
    ]
)
