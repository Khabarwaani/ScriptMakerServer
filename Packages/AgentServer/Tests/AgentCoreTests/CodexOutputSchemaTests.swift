import Foundation
import Testing

@testable import AgentCore

@Test func codexStrictSchemaKeepsDomainOptionalFieldsOptional() throws {
    let schema = try JSONValue.parse(#"{"type":"object","additionalProperties":false,"required":["required"],"properties":{"required":{"type":"string"},"optional":{"type":"array","items":{"type":"string"}},"nullable":{"type":["string","null"]},"location":{"type":["object","string"],"properties":{"city":{"type":"string"}},"additionalProperties":false}}}"#)
    let strict = try #require(CodexOutputSchema.make(schema))
    #expect(Set(strict["required"]!.array!.compactMap(\.string)) == ["required", "optional", "nullable", "location"])
    let transported = try JSONValue.parse(#"{"required":"kept","optional":null,"nullable":null,"location":{"city":null}}"#)
    try OutputValidator.validate(transported, schema: strict)
    let result = CodexOutputSchema.normalize(transported, schema: schema)
    #expect(result == .object(["required": .string("kept"), "nullable": .null, "location": .object([:])]))
    try OutputValidator.validate(result, schema: schema)
    let invalid = try JSONValue.parse(#"{"required":null,"unknown":null}"#)
    let normalized = CodexOutputSchema.normalize(invalid, schema: schema)
    #expect(normalized["required"] == .null && normalized["unknown"] == .null)
    #expect(throws: AgentError.self) { try OutputValidator.validate(normalized, schema: schema) }
}

@Test func codexSchemaConvertsRegisteredNewsAndArrayItems() async throws {
    let definition = try await AgentRegistry().resolve(id: "NewsResearcher", version: "1.1.0")
    let strict = try #require(CodexOutputSchema.make(definition.outputSchema))
    let raw = try JSONValue.parse(#"{"verified":true,"confidence":95,"date":"13-10-26","location":null,"people":null,"notes":null,"hashtags":null}"#)
    try OutputValidator.validate(raw, schema: strict)
    let normalized = CodexOutputSchema.normalize(raw, schema: definition.outputSchema)
    #expect(normalized.object?.count == 3)
    try OutputValidator.validate(normalized, schema: definition.outputSchema)
    let array = try JSONValue.parse(#"{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"optional":{"type":"integer"}}}}"#)
    #expect(CodexOutputSchema.normalize(.array([.object(["optional": .null])]), schema: array) == .array([.object([:])]))
}

@Test func unsupportedCodexNativeSchemasUseServerValidation() throws {
    let dynamic = try JSONValue.parse(#"{"type":"object","additionalProperties":true}"#)
    #expect(CodexOutputSchema.make(dynamic) == nil)
    #expect(CodexOutputSchema.make(try JSONValue.parse(#"{"allOf":[{"type":"object"}]}"#)) == nil)
}
