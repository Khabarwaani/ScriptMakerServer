// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AgentSpec",
    platforms: [.macOS(.v14), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [.library(name: "AgentSpec", targets: ["AgentSpec"])],
    dependencies: [
        .package(url: "https://github.com/ajevans99/swift-json-schema.git", exact: "0.14.2"),
        .package(url: "https://github.com/Kitura/TypeDecoder.git", exact: "2.0.0")
    ],
    targets: [
        .target(
            name: "AgentSpec",
            dependencies: [
                .product(
                    name: "JSONSchema",
                    package: "swift-json-schema",
                    moduleAliases: ["JSONSchema": "SchemaValidation"]
                ),
                .product(name: "TypeDecoder", package: "TypeDecoder")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
