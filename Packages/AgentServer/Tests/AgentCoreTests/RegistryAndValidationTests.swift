import Foundation
import Testing

@testable import AgentCore

struct EchoPackage: AgentPackageContract {
    static let id = "Echo"
    static let versions = ["1.0.0", "1.1.0", "2.0.0-beta.1"]

    static func directory(version: String) throws -> URL {
        URL(fileURLWithPath: "/tmp/Echo/\(version)")
    }

    static func role(version: String) throws -> String {
        "You are the Echo agent responsible for processing supplied JSON input and returning a structured result."
    }

    static func instructions(version: String) throws -> String {
        "Process supplied JSON data and return one object matching output.schema.json."
    }

    static func outputSchema(version: String) throws -> String {
        #"{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["result"],"properties":{"result":{"type":"string"}}}"#
    }

    static func inputSchema(version: String) throws -> String? {
        nil
    }
}

private struct InvalidEchoPackage: AgentPackageContract {
    static let id = "Echo"
    static let versions = ["1.0.0"]
    static func directory(version: String) throws -> URL { URL(fileURLWithPath: "/tmp/invalid") }
    static func role(version: String) throws -> String { "Invalid role without period" }
    static func instructions(version: String) throws -> String { "instructions" }
    static func outputSchema(version: String) throws -> String {
        #"{"type":"object","unevaluatedProperties":false}"#
    }
    static func inputSchema(version: String) throws -> String? { nil }
}

private enum MutableInstructionPackage: AgentPackageContract {
    static let id = "MutableAgent"
    static let versions = ["1.0.0"]
    nonisolated(unsafe) static var instructionText = "Original instructions."
    static func directory(version: String) throws -> URL { URL(fileURLWithPath: "/tmp/MutableAgent/1.0.0") }
    static func role(version: String) throws -> String { "Role statement." }
    static func instructions(version: String) throws -> String { instructionText }
    static func outputSchema(version: String) throws -> String {
        #"{"type":"object","additionalProperties":false,"required":["result"],"properties":{"result":{"type":"string"}}}"#
    }
    static func inputSchema(version: String) throws -> String? { nil }
}

final class AgentFixture: Sendable {
    let directory: URL
    let agents: URL
    let runtime: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        agents = directory.appendingPathComponent("Agents", isDirectory: true)
        runtime = directory.appendingPathComponent("Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try AgentPackageTools.create(id: "Echo", root: agents)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

@Test func packageCreationAndRuntimeDiscovery() async throws {
    let fixture = try AgentFixture()
    try AgentPackageTools.create(id: "Writer", root: fixture.agents)
    try AgentPackageTools.addVersion(
        id: "Echo", version: "1.1.0", sourceVersion: "1.0.0", root: fixture.agents)
    try AgentPackageTools.addVersion(
        id: "Echo", version: "2.0.0-beta.1", sourceVersion: "1.0.0", root: fixture.agents)
    let issues = try AgentPackageTools.check(root: fixture.agents, registeredPackages: [EchoPackage.self])
    // Unregistered Writer package is flagged
    #expect(issues.contains(where: { $0.contains("Writer: package is not registered") }))
    // But Echo has no issues
    #expect(!issues.contains(where: { $0.contains("Echo:") }))

    let registry = AgentRegistry(packages: [EchoPackage.self], root: fixture.agents)

    // Only registered packages are listed; unregistered Writer directory is excluded
    #expect(await registry.list().count == 1)
    #expect(try await registry.resolve(id: "Echo", version: nil).version == "1.1.0")
    #expect(try await registry.resolve(id: "Echo", version: "1.0.0").version == "1.0.0")
    #expect(try await registry.resolve(id: "Echo", version: "2.0.0-beta.1").version == "2.0.0-beta.1")
    await #expect(throws: AgentError.self) { try await registry.resolve(id: "Echo", version: "9.0.0") }
    await #expect(throws: AgentError.self) { try await registry.resolve(id: "Missing", version: nil) }
    // Unregistered directory Writer is rejected with invalid_agent_definition
    await #expect(throws: AgentError.self) { try await registry.resolve(id: "Writer", version: nil) }
}

@Test func registeredLinkedPackagesAreAvailableByDefault() async throws {
    let registry = AgentRegistry()
    let agents = await registry.list()
    #expect(agents.count == 2)
    #expect(agents.map(\.id).contains("NewsResearcher"))
    #expect(agents.map(\.id).contains("ScriptWriter"))
    #expect(try await registry.resolve(id: "NewsResearcher", version: nil).version == "1.1.0")
    #expect(try await registry.resolve(id: "ScriptWriter", version: nil).version == "1.1.0")
}

@Test func invalidDefinitionsAndTraversalAreUnavailable() async throws {
    let fixture = try AgentFixture()
    let schema = fixture.agents.appendingPathComponent("Echo/1.0.0/output.schema.json")
    try #"{"type":"object","unevaluatedProperties":false}"#.write(
        to: schema, atomically: true, encoding: .utf8)
    let registry = AgentRegistry(packages: [InvalidEchoPackage.self], root: fixture.agents)
    #expect(await registry.list().isEmpty)
    await #expect(throws: AgentError.self) { try await registry.resolve(id: "../Echo", version: nil) }
    await #expect(throws: AgentError.self) { try await registry.resolve(id: "Echo", version: nil) }
    #expect(!((try AgentPackageTools.check(root: fixture.agents)).isEmpty))
    #expect(throws: AgentError.self) { try AgentPackageTools.create(id: "../Bad", root: fixture.agents) }
    #expect(throws: AgentError.self) { try AgentPackageTools.create(id: "Echo", root: fixture.agents) }
}

@Test func executionDefinitionIsAnImmutableSnapshot() async throws {
    MutableInstructionPackage.instructionText = "Original instructions."
    let registry = AgentRegistry(packages: [MutableInstructionPackage.self])
    let before = try await registry.resolve(id: "MutableAgent", version: nil)
    MutableInstructionPackage.instructionText = "Changed instructions."
    let after = try await registry.resolve(id: "MutableAgent", version: nil)
    #expect(before.instructions == after.instructions)
}

@Test(arguments: ["1.0", "01.0.0", "1.0.0-01", "1.0.0/../../", "", "v1.0.0"])
func invalidSemanticVersions(value: String) { #expect(SemanticVersion(value) == nil) }

@Test func semanticVersionPrecedence() {
    let ordered = [
        "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11",
        "1.0.0-rc.1", "1.0.0", "1.1.0", "2.0.0",
    ]
    #expect(ordered.reversed().compactMap(SemanticVersion.init).sorted().map(\.raw) == ordered)
    #expect(SemanticVersion("1.0.0+abc") == SemanticVersion("1.0.0+def"))
}

@Test func strictSchemaValidatesAndRejectsExtraFields() throws {
    let schema = try JSONValue.parse(
        #"{"type":"object","additionalProperties":false,"required":["result"],"properties":{"result":{"type":"string","minLength":1}}}"#
    )
    try OutputValidator.checkSchema(schema)
    try OutputValidator.validate(.object(["result": .string("hello")]), schema: schema)
    #expect(throws: AgentError.self) {
        try OutputValidator.validate(
            .object(["result": .string("hello"), "toolAction": .string("metadata")]), schema: schema)
    }
    #expect(throws: AgentError.self) {
        try OutputValidator.validate(.object(["result": .number(1)]), schema: schema)
    }
    #expect(throws: AgentError.self) {
        try OutputValidator.checkSchema(JSONValue.parse(#"{"format":"email"}"#))
    }
}

@Test func schemaReferencesArraysAndCompositions() throws {
    let schema = try JSONValue.parse(
        ##"{"$defs":{"item":{"type":"integer","minimum":1}},"type":"array","items":{"$ref":"#/$defs/item"},"uniqueItems":true,"minItems":2}"##
    )
    try OutputValidator.checkSchema(schema)
    try OutputValidator.validate(.array([.number(1), .number(2)]), schema: schema)
    #expect(throws: AgentError.self) {
        try OutputValidator.validate(.array([.number(1), .number(1)]), schema: schema)
    }
    #expect(throws: AgentError.self) {
        try OutputValidator.validate(.array([.number(0), .number(2)]), schema: schema)
    }
    let choice = try JSONValue.parse(#"{"oneOf":[{"type":"string","pattern":"^ok$"},{"const":42}]}"#)
    try OutputValidator.validate(.string("ok"), schema: choice)
    #expect(throws: AgentError.self) { try OutputValidator.validate(.string("bad"), schema: choice) }
}

@Test func buildTimeValidationAndMetadataVerification() async throws {
    let fixture = try AgentFixture()
    let echoDir = fixture.agents.appendingPathComponent("Echo")

    // 1. Successful validation produces metadata with SHA256 hashes
    let metadata = try AgentPackageValidator.validate(packageDirectory: echoDir)
    #expect(metadata.agentId == "Echo")
    #expect(metadata.versions.count == 1)
    #expect(metadata.versions[0].version == "1.0.0")
    #expect(metadata.versions[0].resourceHashes["role.md"] != nil)
    #expect(metadata.versions[0].resourceHashes["output.schema.json"] != nil)

    // 2. Modifying a resource invalidates metadata verification in registry
    let versionMeta = metadata.versions[0]
    let alteredMeta = AgentValidationMetadata(agentId: "Echo", versions: [
        AgentValidationMetadata.VersionMetadata(
            version: "1.0.0",
            resourceHashes: ["role.md": "tampered_hash_value_12345"]
        )
    ])

    struct MockPackageWithDir: AgentPackageContract {
        static let id = "Echo"
        static let versions = ["1.0.0"]
        nonisolated(unsafe) static var dirURL: URL = URL(fileURLWithPath: "/tmp")
        static func directory(version: String) throws -> URL { dirURL }
        static func role(version: String) throws -> String {
            try String(contentsOf: dirURL.appendingPathComponent("role.md"), encoding: .utf8)
        }
        static func instructions(version: String) throws -> String {
            try String(contentsOf: dirURL.appendingPathComponent("instructions.md"), encoding: .utf8)
        }
        static func outputSchema(version: String) throws -> String {
            try String(contentsOf: dirURL.appendingPathComponent("output.schema.json"), encoding: .utf8)
        }
        static func inputSchema(version: String) throws -> String? { nil }
    }
    MockPackageWithDir.dirURL = echoDir.appendingPathComponent("1.0.0")

    // Passing altered metadata should cause AgentRegistry to reject the unverified version
    let registryWithBadMeta = AgentRegistry(
        packages: [MockPackageWithDir.self],
        validationMetadata: [alteredMeta],
        root: fixture.agents
    )
    #expect(await registryWithBadMeta.list().isEmpty)

    // Passing matching metadata allows registration
    let registryWithGoodMeta = AgentRegistry(
        packages: [MockPackageWithDir.self],
        validationMetadata: [metadata],
        root: fixture.agents
    )
    #expect(await registryWithGoodMeta.list().count == 1)

    // 3. Validation fails for malformed schema JSON
    let badSchemaFile = echoDir.appendingPathComponent("1.0.0/output.schema.json")
    try "{ bad json".write(to: badSchemaFile, atomically: true, encoding: .utf8)
    #expect(throws: AgentPackageValidator.ValidationError.self) {
        try AgentPackageValidator.validate(packageDirectory: echoDir)
    }

    // 4. Validation fails for unsupported schema constraint
    try #"{"type":"object","unsupportedKeyword":true}"#.write(to: badSchemaFile, atomically: true, encoding: .utf8)
    #expect(throws: AgentPackageValidator.ValidationError.self) {
        try AgentPackageValidator.validate(packageDirectory: echoDir)
    }

    // 5. Validation fails for invalid schema example
    let invalidExampleSchema = #"""
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["result"],
      "properties": {
        "result": { "type": "string" }
      },
      "examples": [{ "result": 12345 }]
    }
    """#
    try invalidExampleSchema.write(to: badSchemaFile, atomically: true, encoding: .utf8)
    #expect(throws: AgentPackageValidator.ValidationError.self) {
        try AgentPackageValidator.validate(packageDirectory: echoDir)
    }
}

@Test func buildTimeDocumentationGeneration() throws {
    let fixture = try AgentFixture()
    let echoDir = fixture.agents.appendingPathComponent("Echo")

    // Add optional notes.md
    let notesFile = echoDir.appendingPathComponent("1.0.0/notes.md")
    try "Custom authored version notes for Echo 1.0.0.".write(to: notesFile, atomically: true, encoding: .utf8)

    let docMeta = try AgentDocumentationGenerator.generate(packageDirectory: echoDir)
    #expect(docMeta.agentId == "Echo")
    #expect(docMeta.versions.count == 1)
    #expect(docMeta.versions[0].version == "1.0.0")
    #expect(docMeta.versions[0].notes == "Custom authored version notes for Echo 1.0.0.")
    #expect(docMeta.readme.contains("# Echo"))
    #expect(docMeta.readme.contains("## Available Versions"))
    #expect(docMeta.readme.contains("Custom authored version notes for Echo 1.0.0."))
}
