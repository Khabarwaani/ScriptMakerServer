import Foundation
import Testing
@testable import AgentCore

@Test func explicitNullIsNotReplacedByDefault() throws {
    let schema = try JSONValue.parse(#"{"type":"object","properties":{"count":{"type":["integer","null"],"default":3}}}"#)
    #expect(try OutputValidator.applyDefaults(to: .object(["count": .null]), schema: schema) == .object(["count": .null]))
}

@Test func defaultsApplyInsideArraysAndReferences() throws {
    let schema = try JSONValue.parse(##"{"type":"object","$defs":{"entry":{"type":"object","properties":{"count":{"type":"integer","default":3}}}},"properties":{"entries":{"type":"array","items":{"$ref":"#/$defs/entry"}}}}"##)
    let input: JSONValue = .object(["entries": .array([.object([:])])])
    #expect(try OutputValidator.applyDefaults(to: input, schema: schema)["entries"] == .array([.object(["count": .number(3)])]))
}

private struct ContractFixture: Sendable, CustomTestStringConvertible {
    let agentID: String
    let version: String
    var testDescription: String { "\(agentID)@\(version)" }
    static let all = AgentRegistry.registeredPackages.flatMap { package in
        package.versions.map { ContractFixture(agentID: package.id, version: $0) }
    }
}

private actor ContractCapture {
    var inputs: [JSONValue] = []
    func record(_ value: JSONValue) { inputs.append(value) }
}

private struct ContractProvider: AIProvider {
    let id = "schema-contract-mock"
    let capture: ContractCapture
    let output: JSONValue
    func checkReadiness() async throws {}
    func execute(definition: AgentDefinition, input: JSONValue, runner: ProcessRunner, directory: URL,
                 timeoutSeconds: Int, onOutput: @escaping @Sendable (String) async -> Void,
                 onProgress: @escaping @Sendable (JSONValue) async -> Void) async throws -> JSONValue {
        await capture.record(input)
        return output
    }
}

@Test(arguments: ContractFixture.all)
private func registeredInputContractsAreTestedWithoutAPIOrLLM(fixture: ContractFixture) async throws {
    let registry = AgentRegistry()
    let definition = try await registry.resolve(id: fixture.agentID, version: fixture.version)
    guard let schema = definition.inputSchema else { return } // No declared input contract to enumerate.
    let examples = try #require(schema["examples"]?.array, "Input contract needs declarative examples for generic tests.")
    #expect(!examples.isEmpty)
    let generator = SchemaInputCases(schema: schema)
    let output = try SchemaInputCases(schema: definition.outputSchema).baseline(
        definition.outputSchema["examples"]?.array?.first ?? .object([:]))
    try OutputValidator.validate(output, schema: definition.outputSchema)
    let capture = ContractCapture()
    let provider = ContractProvider(capture: capture, output: output)
    let runtime = FileManager.default.temporaryDirectory.appendingPathComponent("InputContracts-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: runtime) }
    let manager = ExecutionManager(registry: registry, providers: ProviderCatalog(providers: [provider]), runtimeRoot: runtime,
        resourceSample: { SystemResources(physical_memory_bytes: 8_589_934_592, available_memory_bytes: 4_294_967_296, load_average: 0, cpu_count: 8) })
    var successful = 0
    var rejected = 0
    for example in examples {
        let baseline = try generator.baseline(example)
        let fields = try generator.fields(in: baseline)
        var cases: [(String, JSONValue, SchemaInputCases.Field?)] = [("baseline", baseline, nil), ("original example", example, nil)]
        for field in fields { cases.append((field.path, SchemaInputCases.removing(baseline, at: field.tokens), field)) }
        let optional = fields.filter { !$0.required }
        let minimal = optional.sorted { $0.tokens.count > $1.tokens.count }.reduce(baseline) {
            SchemaInputCases.removing($0, at: $1.tokens)
        }
        cases.append(("all optional fields omitted", minimal, nil))
        for (label, input, field) in cases {
            // A parent object default can restore a required nested member too.
            let fallback = try field.map { try generator.defaultValue(for: $0, in: baseline) } ?? nil
            let mustFail = field?.required == true && fallback == nil
            let before = await capture.inputs.count
            if mustFail {
                do {
                    _ = try await manager.execute(ExecuteRequest(agentID: fixture.agentID, version: fixture.version, provider: provider.id, input: input))
                    Issue.record("Missing required field was accepted: \(label)")
                } catch let error as AgentError {
                    #expect(error.code == "input_schema_validation_failed", "\(label)")
                    let violations = try #require(error.details?["violations"]?.array)
                    #expect(violations.contains { $0["path"] == .string(label) && $0["keyword"] == .string("required") && $0["actual"] == .string("missing") })
                }
                #expect(await capture.inputs.count == before)
                rejected += 1
            } else {
                let effective = try InputValidator.prepare(input, schema: schema, agentID: fixture.agentID, version: fixture.version)
                try OutputValidator.validate(effective, schema: schema)
                #expect(try InputValidator.prepare(effective, schema: schema, agentID: fixture.agentID, version: fixture.version) == effective)
                if let field {
                    if let fallback {
                        #expect(SchemaInputCases.value(effective, at: field.tokens) == fallback, "Default at \(label)")
                    } else {
                        #expect(SchemaInputCases.value(effective, at: field.tokens) == nil, "Optional field \(label) must remain absent")
                    }
                }
                // Every supplied leaf survives preparation, including values unrelated to this omission.
                for present in fields {
                    if let value = SchemaInputCases.value(input, at: present.tokens), value.object == nil, value.array == nil {
                        #expect(SchemaInputCases.value(effective, at: present.tokens) == value)
                    }
                }
                let accepted = try await manager.execute(ExecuteRequest(agentID: fixture.agentID, version: fixture.version, provider: provider.id, input: input))
                let stream = await events(accepted)
                #expect(stream.last?.name == "completed", "\(label): \(stream.last?.data ?? .null)")
                #expect(await capture.inputs.count == before + 1)
                #expect(await capture.inputs.last == effective)
                successful += 1
            }
        }
    }
    await manager.shutdown(timeoutSeconds: 0)
    print("Input contracts \(fixture.testDescription): \(successful) passed, \(rejected) rejected as expected; no HTTP or LLM calls.")
}

@Test func missingAndInvalidFieldsHaveDetailedSafeErrors() throws {
    let schema = try JSONValue.parse(#"{"type":"object","required":["script","items","a/b~"],"properties":{"script":{"type":"string"},"a/b~":{"type":"string"},"items":{"type":"array","items":{"type":"object","required":["category"],"properties":{"category":{"type":"string"},"count":{"type":"integer","minimum":1}}}}}}"#)
    let input: JSONValue = .object(["items": .array([.object(["count": .number(0)])])])
    do {
        _ = try InputValidator.prepare(input, schema: schema, agentID: "Fixture", version: "1.0.0")
        Issue.record("Invalid input was accepted")
    } catch let error as AgentError {
        #expect(error.httpStatus == 400)
        let details = try #require(error.details)
        let failures = try #require(details["violations"]?.array)
        #expect(failures.compactMap { $0["path"]?.string } == ["/a~1b~0", "/items/0/category", "/items/0/count", "/script"])
        #expect(failures.first?["field"] == .string("a/b~"))
        #expect(failures.last?["expected"] == .object(["required": .bool(true), "type": .string("string")]))
        #expect(failures.last?["actual"] == .string("missing"))
        #expect(details["agent_id"] == .string("Fixture"))
        let roundTrip = try JSONDecoder().decode(AgentError.self, from: JSONEncoder().encode(error))
        #expect(roundTrip == error)
        let event = StreamEvent(name: "failed", data: .object(["error": try JSONValue.parse(String(decoding: JSONEncoder().encode(error), as: UTF8.self))]))
        #expect(event.data["error"]?["details"] == details)
    }
}

@Test func requiredDefaultsAndExplicitInvalidValues() throws {
    let schema = try JSONValue.parse(#"{"type":"object","required":["count"],"properties":{"count":{"type":"integer","minimum":1,"default":3},"optional":{"type":"string"}}}"#)
    #expect(try InputValidator.prepare(.object([:]), schema: schema, agentID: "Fixture", version: "1.0.0") == .object(["count": .number(3)]))
    for value in [JSONValue.null, .string("secret-value"), .number(0)] {
        do {
            _ = try InputValidator.prepare(.object(["count": value]), schema: schema, agentID: "Fixture", version: "1.0.0")
            Issue.record("Invalid explicit value was accepted")
        } catch let error as AgentError {
            #expect(error.details?["violations"]?.array?.first?["path"] == .string("/count"))
            #expect(!(try JSONEncoder().encode(error)).contains(Data("secret-value".utf8)))
        }
    }
}

@Test func invalidDefaultsConflictsAndLimits() throws {
    let invalid = try JSONValue.parse(#"{"type":"object","properties":{"count":{"type":"integer","default":"wrong"}}}"#)
    #expect(throws: AgentError.self) { try OutputValidator.checkSchema(invalid) }
    let conflict = try JSONValue.parse(#"{"allOf":[{"properties":{"count":{"default":1}}},{"properties":{"count":{"default":2}}}]}"#)
    #expect(throws: AgentError.self) { try OutputValidator.applyDefaults(to: .object([:]), schema: conflict) }
    #expect(throws: AgentError.self) { try OutputValidator.checkSchema(conflict) }
    let cycle = try JSONValue.parse(##"{"$ref":"#"}"##)
    #expect(throws: AgentError.self) { try OutputValidator.applyDefaults(to: .object([:]), schema: cycle) }
    let keys = (0..<55).map { "field\($0)" }
    let schema: JSONValue = .object(["type": .string("object"), "required": .array(keys.map(JSONValue.string))])
    do {
        _ = try InputValidator.prepare(.object([:]), schema: schema, agentID: "Fixture", version: "1.0.0")
        Issue.record("Missing fields were accepted")
    } catch let error as AgentError {
        #expect(error.details?["violations"]?.array?.count == 50)
        #expect(error.details?["truncated"] == .bool(true))
    }
}

@Test func compositionAndTupleDefaultsAreDeterministic() throws {
    let schema = try JSONValue.parse(##"{"type":"object","$defs":{"entry":{"type":"object","properties":{"label":{"type":"string","default":"ready"}}}},"allOf":[{"properties":{"count":{"type":"integer","default":2}}},{"properties":{"mode":{"type":"string","default":"fast"}}}],"properties":{"entries":{"type":"array","prefixItems":[{"$ref":"#/$defs/entry"}],"items":{"$ref":"#/$defs/entry"}}}}"##)
    let input: JSONValue = .object(["entries": .array([.object([:]), .object(["label": .string("custom")])])])
    let effective = try InputValidator.prepare(input, schema: schema, agentID: "Fixture", version: "1.0.0")
    #expect(effective["count"] == .number(2))
    #expect(effective["mode"] == .string("fast"))
    #expect(effective["entries"] == .array([.object(["label": .string("ready")]), .object(["label": .string("custom")])]))
    let alternative = try JSONValue.parse(#"{"oneOf":[{"required":["kind"],"properties":{"kind":{"const":"a"},"count":{"default":1}}},{"required":["kind"],"properties":{"kind":{"const":"b"},"count":{"default":2}}}]}"#)
    #expect(try OutputValidator.applyDefaults(to: .object(["kind": .string("b")]), schema: alternative)["count"] == .number(2))
    let ambiguous = try JSONValue.parse(#"{"anyOf":[{"properties":{"count":{"default":1}}},{"properties":{"count":{"default":2}}}]}"#)
    #expect(throws: AgentError.self) { try OutputValidator.applyDefaults(to: .object([:]), schema: ambiguous) }
    let conditional = try JSONValue.parse(#"{"if":{"required":["enabled"],"properties":{"enabled":{"const":true}}},"then":{"properties":{"count":{"default":1}}},"else":{"properties":{"count":{"default":2}}}}"#)
    #expect(try OutputValidator.applyDefaults(to: .object(["enabled": .bool(true)]), schema: conditional)["count"] == .number(1))
    #expect(try OutputValidator.applyDefaults(to: .object([:]), schema: conditional)["count"] == .number(2))
    let indexedRef = try JSONValue.parse(##"{"$defs":{"tuple":{"oneOf":[{"type":"integer","default":4}]}},"properties":{"count":{"$ref":"#/$defs/tuple/oneOf/0"}}}"##)
    try OutputValidator.checkSchema(indexedRef)
    #expect(try OutputValidator.applyDefaults(to: .object([:]), schema: indexedRef)["count"] == .number(4))
}

@Test func genericGeneratorDiscoversChangedFieldsAndReportsCoverageGaps() throws {
    for extraName in ["newOption", "anotherField"] {
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object([
            extraName: .object(["type": .string("integer"), "default": .number(7)]),
            "items": .object(["type": .string("array"), "items": .object([
                "$ref": .string("#/$defs/entry")])]),
        ]), "$defs": .object(["entry": .object(["type": .string("object"), "properties": .object([
            "nested": .object(["type": .string("boolean")]),
        ])])])])
        let generator = SchemaInputCases(schema: schema)
        let baseline = try generator.baseline(.object([:]))
        let fields = try generator.fields(in: baseline)
        #expect(fields.contains { $0.path == "/\(extraName)" })
        #expect(fields.contains { $0.path == "/items/0/nested" })
        for field in fields where !field.required {
            _ = try InputValidator.prepare(SchemaInputCases.removing(baseline, at: field.tokens), schema: schema, agentID: "Fixture", version: "1.0.0")
        }
    }
    let schema = try JSONValue.parse(#"{"type":"object","properties":{"value":{"type":"string","pattern":"^unusual-pattern$"}}}"#)
    #expect(throws: AgentError.self) { try SchemaInputCases(schema: schema).baseline(.object([:])) }
}

@Test func nestedObjectDefaultsMergeWithoutReplacingSuppliedLeaves() throws {
    let schema = try JSONValue.parse(#"{"type":"object","required":["settings"],"default":{"settings":{"limits":{"min":1,"max":5}}},"properties":{"settings":{"type":"object","required":["limits"],"properties":{"limits":{"type":"object","required":["min","max"],"properties":{"min":{"type":["integer","null"]},"max":{"type":"integer"}}}}}}}"#)
    let input: JSONValue = .object(["settings": .object(["limits": .object(["min": .null])])])
    let effective = try InputValidator.prepare(input, schema: schema, agentID: "Fixture", version: "1.0.0")
    #expect(effective["settings"]?["limits"] == .object(["min": .null, "max": .number(5)]))
    let generator = SchemaInputCases(schema: schema)
    let baseline = try generator.baseline(.object([:]))
    for field in try generator.fields(in: baseline) {
        let fallback = try #require(try generator.defaultValue(for: field, in: baseline))
        let prepared = try InputValidator.prepare(SchemaInputCases.removing(baseline, at: field.tokens), schema: schema, agentID: "Fixture", version: "1.0.0")
        #expect(SchemaInputCases.value(prepared, at: field.tokens) == fallback)
    }
}
