// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NewsResearcher", platforms: [.macOS(.v14)],
    products: [.library(name: "NewsResearcher", targets: ["NewsResearcher"])],
    targets: [
        .target(name: "NewsResearcher", path: ".", exclude: ["Tests", "README.md"],
                sources: ["Sources/NewsResearcher/NewsResearcher.swift"], resources: [.copy("1.1.0")]),
        .testTarget(name: "NewsResearcherTests", dependencies: ["NewsResearcher"])
    ]
)
