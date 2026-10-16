// swift-tools-version: 6.0
import PackageDescription

// Command-line tools load the distributed framework beside their executable.
let frameworkLinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path"], .when(platforms: [.macOS]))
]

let package = Package(
    name: "AgentServer",
    platforms: [.macOS("27.0")],
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
        .package(path: "Agents/DialogueRefiner"),
        .package(path: "Agents/ReelIdeaGenerator"),
        .package(path: "Agents/DialogueGenerator"),
        .package(path: "Agents/ThemeMixer"),
        .package(path: "Agents/ReelJokeMaker"),
        .package(path: "Agents/ShekharJokeGenerator"),
        .package(path: "../AgentCoreBase"),
        .package(path: "../ScriptDomainModels"),
        .package(url: "https://github.com/abhi266raj/TerminalAgentSession", exact: "0.1.4"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.27.1"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.12.1")
    ],
    targets: [
        .target(
            name: "AgentCore",
            dependencies: [
                .product(name: "AgentCoreBase", package: "AgentCoreBase"),
                .product(name: "ScriptDomainModels", package: "ScriptDomainModels"),
                .product(name: "TerminalAgentSession", package: "TerminalAgentSession"),
                .product(name: "NewsResearcher", package: "NewsResearcher"),
                .product(name: "ScriptRefiner", package: "ScriptRefiner"),
                .product(name: "DialogueRefiner", package: "DialogueRefiner"),
                .product(name: "ReelIdeaGenerator", package: "ReelIdeaGenerator"),
                .product(name: "DialogueGenerator", package: "DialogueGenerator"),
                .product(name: "ThemeMixer", package: "ThemeMixer"),
                .product(name: "ReelJokeMaker", package: "ReelJokeMaker"),
                .product(name: "ShekharJokeGenerator", package: "ShekharJokeGenerator"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .target(name: "AgentResources", path: ".", exclude: [
            "Sources/AgentCore", "Sources/AgentServer", "Sources/AgentTools", "Sources/AgentValidator", "Plugins", "Tests", "AGENTS.md", "README.md", "Agents"
        ], sources: ["Sources/AgentResources/AgentResources.swift"], resources: [
            .copy("Sources/AgentResources/Web"), .copy("config")
        ]),
        .executableTarget(name: "AgentTools", dependencies: ["AgentCore"], linkerSettings: frameworkLinkerSettings),
        .executableTarget(name: "AgentValidator", dependencies: ["AgentCore"], linkerSettings: frameworkLinkerSettings),
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
                .product(name: "TerminalAgentSession", package: "TerminalAgentSession"),
                .product(name: "NewsResearcher", package: "NewsResearcher"),
                .product(name: "ScriptRefiner", package: "ScriptRefiner"),
                .product(name: "DialogueRefiner", package: "DialogueRefiner"),
                .product(name: "ReelIdeaGenerator", package: "ReelIdeaGenerator"),
                .product(name: "DialogueGenerator", package: "DialogueGenerator"),
                .product(name: "ThemeMixer", package: "ThemeMixer"),
                .product(name: "ReelJokeMaker", package: "ReelJokeMaker"),
                .product(name: "ShekharJokeGenerator", package: "ShekharJokeGenerator"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle")
            ],
            linkerSettings: frameworkLinkerSettings,
            plugins: ["ValidateAgentsPlugin"]
        ),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore", .product(name: "ShekharJokeGenerator", package: "ShekharJokeGenerator")], exclude: ["Fixtures"]),
        .testTarget(name: "AgentServerTests", dependencies: ["AgentServer", "AgentCore", .product(name: "HummingbirdTesting", package: "hummingbird")])
    ]
)
