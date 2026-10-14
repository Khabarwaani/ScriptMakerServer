@testable import AgentAtom
import Foundation
import Testing

struct ContractTests {
    @Test
    func testModelledSpecDefaultsAndOutputStorage() throws {
        var spec = Example(input: .init(text: "hello", count: 2))
        #expect(Example.identity == Identity(id: "example", name: "Example", version: "1"))
        #expect(Example.role == "Summarise")
        #expect(spec.instructions == "Be concise")
        #expect(spec.inputJSON.rawValue == #"{"count":2,"text":"hello"}"#)
        #expect(spec.output == nil)
        spec.output = try JSONDecoder().decode(ExampleOutput.self, from: Data(#"{"result":"done"}"#.utf8))
        #expect(spec.output?.result == "done")
        #expect(JSONString(Example.outputSchema.rawValue) != nil)
        spec.output = nil
        #expect(spec.output == nil)
    }

    @Test
    func testExplicitPropertiesReplaceDefaults() {
        let spec = Overridden()
        #expect(spec.inputJSON.rawValue == "null")
        #expect(Overridden.outputSchema == JSONSchema(String.self))
    }
}

private struct ExampleInput: Encodable, Sendable {
    let text: String
    let count: Int
}

private struct ExampleOutput: Decodable, Sendable {
    let result: String
}

private struct Example: ModelledSpec {
    static let identity = Identity(id: "example", name: "Example", version: "1")
    static let role = "Summarise"
    let instructions = "Be concise"
    let input: ExampleInput
    var output: ExampleOutput?
}

private struct Overridden: ModelledSpec {
    static let identity = Example.identity
    static let role = Example.role
    static let outputSchema = JSONSchema(String.self)!
    let instructions = "Override"
    let input = ExampleInput(text: "unused", count: 0)
    let inputJSON: JSONString = "null"
    var output: ExampleOutput?
}
