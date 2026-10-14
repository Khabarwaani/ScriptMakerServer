import Foundation
import Testing
@testable import AgentCoreBase

@Test func schemaBuilderCreatesValidSchema() throws {
    let schema = SchemaDefinition(
        title: "TestSchema",
        properties: [
            SchemaProperty(name: "query", type: "string", required: true)
        ],
        additionalProperties: false,
        examples: [
            .object(["query": .string("test")])
        ]
    )
    let json = schema.toJSONValue()
    #expect(json["title"] == .string("TestSchema"))
    #expect(json["examples"] != nil)
}
