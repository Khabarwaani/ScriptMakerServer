// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentServer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentServer", targets: ["AgentServer"]),
        .library(name: "AgentCore", targets: ["AgentCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
    ],
    targets: [
        .target(name: "AgentCore"),
        .executableTarget(name: "AgentServer", dependencies: [
            "AgentCore",
            .product(name: "Hummingbird", package: "hummingbird")
        ], resources: [.copy("Web")]),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"])
    ]
)
