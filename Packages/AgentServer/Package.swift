// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentServer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentServer", targets: ["AgentServer"]),
        .executable(name: "AgentTools", targets: ["AgentTools"]),
        .executable(name: "AgentValidator", targets: ["AgentValidator"]),
        .plugin(name: "ValidateAgentsPlugin", targets: ["ValidateAgentsPlugin"]),
        .library(name: "AgentCore", targets: ["AgentCore"])
    ],
    dependencies: [
        .package(path: "Agents/NewsResearcher"),
        .package(path: "Agents/ScriptRefiner"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.27.1"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.12.1")
    ],
    targets: [
        .target(
            name: "AgentCore",
            dependencies: [
                .product(name: "NewsResearcher", package: "NewsResearcher"),
                .product(name: "ScriptRefiner", package: "ScriptRefiner"),
            ]
        ),
        .target(name: "AgentResources", path: ".", exclude: [
            "Sources/AgentCore", "Sources/AgentServer", "Sources/AgentTools", "Sources/AgentValidator", "Plugins", "Tests", "AGENTS.md", "README.md", "Agents"
        ], sources: ["Sources/AgentResources/AgentResources.swift"], resources: [
            .copy("Sources/AgentResources/Web"), .copy("config")
        ]),
        .executableTarget(name: "AgentTools", dependencies: ["AgentCore"]),
        .executableTarget(name: "AgentValidator", dependencies: ["AgentCore"]),
        .plugin(
            name: "ValidateAgentsPlugin",
            capability: .buildTool(),
            dependencies: ["AgentValidator"]
        ),
        .executableTarget(
            name: "AgentServer",
            dependencies: [
                "AgentCore",
                "AgentResources",
                .product(name: "NewsResearcher", package: "NewsResearcher"),
                .product(name: "ScriptRefiner", package: "ScriptRefiner"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle")
            ],
            plugins: ["ValidateAgentsPlugin"]
        ),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"], exclude: ["Fixtures"]),
        .testTarget(name: "AgentServerTests", dependencies: ["AgentServer", "AgentCore", .product(name: "HummingbirdTesting", package: "hummingbird")])
    ]
)
