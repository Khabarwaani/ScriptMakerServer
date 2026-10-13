// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ThemeMixer", platforms: [.macOS(.v14)],
    products: [.library(name: "ThemeMixer", targets: ["ThemeMixer"])],
    targets: [
        .target(name: "ThemeMixer", path: ".", exclude: ["Tests", "README.md"],
                sources: ["Sources/ThemeMixer/ThemeMixer.swift"], resources: [.copy("1.0.0"), .copy("1.1.0")]),
        .testTarget(name: "ThemeMixerTests", dependencies: ["ThemeMixer"])
    ]
)
