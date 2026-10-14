// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentAtom",
    platforms: [.macOS(.v14), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [.library(name: "AgentAtom", targets: ["AgentAtom"])],
    dependencies: [
        .package(url: "https://github.com/Kitura/TypeDecoder.git", exact: "2.0.0")
    ],
    targets: [
        .target(
            name: "AgentAtom",
            dependencies: [
                .product(name: "TypeDecoder", package: "TypeDecoder")
            ]
        ),
        .executableTarget(
            name: "FailureProbe",
            dependencies: ["AgentAtom"],
            path: "Tests/FailureProbe"
        ),
        .testTarget(name: "AgentAtomTests", dependencies: ["AgentAtom", "FailureProbe"])
    ],
    swiftLanguageModes: [.v6]
)
