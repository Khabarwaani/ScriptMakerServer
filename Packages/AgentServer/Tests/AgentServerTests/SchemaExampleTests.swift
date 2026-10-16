import Testing
import AgentCore
import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func inputExample(schema: JSONValue) throws -> JSONValue {
    let context = try #require(JSContext())
    // JavaScriptCore lacks the browser's structuredClone; fixtures contain JSON only.
    context.evaluateScript("function structuredClone(value) { return JSON.parse(JSON.stringify(value)); }")
    let script = try String(contentsOf: packageRoot.appendingPathComponent("Sources/AgentResources/Web/schema-form.js"), encoding: .utf8)
    context.evaluateScript(script)
    #expect(context.exception == nil)
    let value = context.evaluateScript("JSON.stringify(schemaInputExample(\(try schema.text())))")
    #expect(context.exception == nil)
    return try JSONValue.parse(#require(value?.toString()))
}

@Test func shekharWebInputMatchesServerDefaults() throws {
    let schema = try JSONValue.parse(String(
        contentsOf: packageRoot.appendingPathComponent("Agents/ShekharJokeGenerator/1.0.0/input.schema.json"), encoding: .utf8))
    let example = try inputExample(schema: schema)
    #expect(example == .object(["output_count": .number(1), "news_count": .number(3), "jokes_per_category": .number(2)]))
    #expect(example == (try InputValidator.prepare(.object([:]), schema: schema, agentID: "ShekharJokeGenerator", version: "1.0.0")))
}

@Test func inputExamplesPreserveValuesAndFillNestedDefaults() throws {
    let schema = try JSONValue.parse(#"""
        {"type":"object","examples":[{"count":0,"enabled":false,"note":null,"settings":{"min":1},"rows":[{}],"custom":"keep"}],
         "properties":{"count":{"type":"integer","default":3},"enabled":{"type":"boolean","default":true},
         "note":{"type":["string","null"],"default":"note"},"unused":{"type":"string"},
         "settings":{"type":"object","default":{"min":2,"max":4},"properties":{"min":{"type":"integer"},"max":{"type":"integer"}}},
         "rows":{"type":"array","items":{"type":"object","properties":{"size":{"type":"integer","default":5}}}}}}
        """#)
    let example = try inputExample(schema: schema)
    #expect(example["count"] == .number(0))
    #expect(example["enabled"] == .bool(false))
    #expect(example["note"] == .null)
    #expect(example["unused"] == nil)
    #expect(example["custom"] == .string("keep"))
    #expect(example["settings"] == .object(["min": .number(1), "max": .number(4)]))
    #expect(example["rows"] == .array([.object(["size": .number(5)])]))
    #expect(example == (try InputValidator.prepare(schema["examples"]!.array!.first!, schema: schema, agentID: "Test", version: "1")))
}

@Test func registeredWebExamplesAgreeWithExecutionDefaults() async throws {
    let catalog = await AgentRegistry().list()
    #expect(!catalog.isEmpty)
    for agent in catalog {
        for definition in agent.definitions {
            guard let schema = definition.input_schema else { continue }
            let example = try inputExample(schema: schema)
            let supplied = schema["examples"]?.array?.first ?? example
            let effective = try InputValidator.prepare(supplied, schema: schema, agentID: agent.id, version: definition.version)
            #expect(example == effective, "\(agent.id)@\(definition.version) web input matches execution")
        }
    }
}

#endif
