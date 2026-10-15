// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TerminalAgentSession",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TerminalAgentSession", targets: ["TerminalAgentSession"])
    ],
    dependencies: [
        .package(path: "../AgentAtom")
    ],
    targets: [
        .target(
            name: "TerminalAgentSession",
            dependencies: [
                .product(name: "AgentAtom", package: "AgentAtom")
            ]
        ),
        .testTarget(
            name: "TerminalAgentSessionTests",
            dependencies: ["TerminalAgentSession"]
        )
    ],
    swiftLanguageModes: [.v6]
)
