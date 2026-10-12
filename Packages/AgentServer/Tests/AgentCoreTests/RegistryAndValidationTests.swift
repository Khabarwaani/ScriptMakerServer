import Foundation
import Testing
@testable import AgentCore

final class AgentFixture: Sendable {
    let directory: URL
    let agents: URL
    let runtime: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
    try AgentPackageTools.addVersion(id: "Echo", version: "1.1.0", sourceVersion: "1.0.0", root: fixture.agents)
    try AgentPackageTools.addVersion(id: "Echo", version: "2.0.0-beta.1", sourceVersion: "1.0.0", root: fixture.agents)
    #expect(try AgentPackageTools.check(root: fixture.agents).isEmpty)
    let registry = AgentRegistry(root: fixture.agents)
    #expect(await registry.list().count == 2)
    #expect(try await registry.resolve(id: "Echo", version: nil).version == "1.1.0")
    #expect(try await registry.resolve(id: "Echo", version: "1.0.0").version == "1.0.0")
    #expect(try await registry.resolve(id: "Echo", version: "2.0.0-beta.1").version == "2.0.0-beta.1")
    await #expect(throws: AgentError.self) { try await registry.resolve(id: "Echo", version: "9.0.0") }
    await #expect(throws: AgentError.self) { try await registry.resolve(id: "Missing", version: nil) }
    try AgentPackageTools.addVersion(id: "Echo", version: "1.2.0", sourceVersion: "1.0.0", root: fixture.agents)
    #expect(try await registry.resolve(id: "Echo", version: nil).version == "1.2.0")
}

@Test func invalidDefinitionsAndTraversalAreUnavailable() async throws {
    let fixture = try AgentFixture()
    let schema = fixture.agents.appendingPathComponent("Echo/1.0.0/output.schema.json")
    try #"{"type":"object","unevaluatedProperties":false}"#.write(to: schema, atomically: true, encoding: .utf8)
    let registry = AgentRegistry(root: fixture.agents)
    #expect(await registry.list().isEmpty)
    await #expect(throws: AgentError.self) { try await registry.resolve(id: "../Echo", version: nil) }
    #expect(!((try AgentPackageTools.check(root: fixture.agents)).isEmpty))
    #expect(throws: AgentError.self) { try AgentPackageTools.create(id: "../Bad", root: fixture.agents) }
    #expect(throws: AgentError.self) { try AgentPackageTools.create(id: "Echo", root: fixture.agents) }
}

@Test func executionDefinitionIsAnImmutableSnapshot() async throws {
    let fixture = try AgentFixture(), registry = AgentRegistry(root: fixture.agents)
    let before = try await registry.resolve(id: "Echo", version: nil)
    try "Changed instructions.".write(to: fixture.agents.appendingPathComponent("Echo/1.0.0/instructions.md"), atomically: true, encoding: .utf8)
    let after = try await registry.resolve(id: "Echo", version: nil)
    #expect(before.instructions == after.instructions)
}

@Test(arguments: ["1.0", "01.0.0", "1.0.0-01", "1.0.0/../../", "", "v1.0.0"])
func invalidSemanticVersions(value: String) { #expect(SemanticVersion(value) == nil) }

@Test func semanticVersionPrecedence() {
    let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.1.0", "2.0.0"]
    #expect(ordered.reversed().compactMap(SemanticVersion.init).sorted().map(\.raw) == ordered)
    #expect(SemanticVersion("1.0.0+abc") == SemanticVersion("1.0.0+def"))
}

@Test func strictSchemaValidatesAndRejectsExtraFields() throws {
    let schema = try JSONValue.parse(#"{"type":"object","additionalProperties":false,"required":["result"],"properties":{"result":{"type":"string","minLength":1}}}"#)
    try OutputValidator.checkSchema(schema)
    try OutputValidator.validate(.object(["result": .string("hello")]), schema: schema)
    #expect(throws: AgentError.self) { try OutputValidator.validate(.object(["result": .string("hello"), "toolAction": .string("metadata")]), schema: schema) }
    #expect(throws: AgentError.self) { try OutputValidator.validate(.object(["result": .number(1)]), schema: schema) }
    #expect(throws: AgentError.self) { try OutputValidator.checkSchema(JSONValue.parse(#"{"format":"email"}"#)) }
}

@Test func schemaReferencesArraysAndCompositions() throws {
    let schema = try JSONValue.parse(##"{"$defs":{"item":{"type":"integer","minimum":1}},"type":"array","items":{"$ref":"#/$defs/item"},"uniqueItems":true,"minItems":2}"##)
    try OutputValidator.checkSchema(schema)
    try OutputValidator.validate(.array([.number(1), .number(2)]), schema: schema)
    #expect(throws: AgentError.self) { try OutputValidator.validate(.array([.number(1), .number(1)]), schema: schema) }
    #expect(throws: AgentError.self) { try OutputValidator.validate(.array([.number(0), .number(2)]), schema: schema) }
    let choice = try JSONValue.parse(#"{"oneOf":[{"type":"string","pattern":"^ok$"},{"const":42}]}"#)
    try OutputValidator.validate(.string("ok"), schema: choice)
    #expect(throws: AgentError.self) { try OutputValidator.validate(.string("bad"), schema: choice) }
}
