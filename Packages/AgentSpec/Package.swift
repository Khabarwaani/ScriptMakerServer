// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentSpec",
    platforms: [.macOS(.v14), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [.library(name: "AgentSpec", targets: ["AgentSpec"])],
    dependencies: [
        .package(url: "https://github.com/Kitura/TypeDecoder.git", exact: "2.0.0")
    ],
    targets: [
        .target(
            name: "AgentSpec",
            dependencies: [
                .product(name: "TypeDecoder", package: "TypeDecoder")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
