// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScriptDomainModels",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScriptDomainModels", targets: ["ScriptDomainModels"])
    ],
    dependencies: [
        .package(path: "../AgentCoreBase")
    ],
    targets: [
        .target(
            name: "ScriptDomainModels",
            dependencies: [
                .product(name: "AgentCoreBase", package: "AgentCoreBase")
            ],
            path: "Sources/ScriptDomainModels"
        ),
        .testTarget(
            name: "ScriptDomainModelsTests",
            dependencies: ["ScriptDomainModels"],
            path: "Tests/ScriptDomainModelsTests"
        )
    ]
)
