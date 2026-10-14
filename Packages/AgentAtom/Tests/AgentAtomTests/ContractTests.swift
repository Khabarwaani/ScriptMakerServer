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

    @Test
    func testJSONStringAcceptsAllShapesAndPreservesText() {
        for text in [" {} \n", "[]", #""hello""#, "42", "-1.25e2", "true", "false", "null"] {
            #expect(JSONString(text)?.rawValue == text, "\(text)")
        }
        for text in ["", "invalid", "{", "{\"a\":}", "NaN", "true false"] {
            #expect(JSONString(text) == nil, "\(text)")
        }
        let literal: JSONString = #"{"b":2,"a":1}"#
        #expect(literal == JSONString(literal.rawValue))
        #expect(literal.description == literal.debugDescription)
        #expect(literal.description.contains("\n"))
        #expect(JSONString(literal.description)?.description == literal.description)
    }

    @Test
    func testJSONStringUsesFoundationAcceptanceRules() {
        for text in ["[1,]", #"{"a":1,}"#, "01", "+1"] {
            let accepted = (try? JSONSerialization.jsonObject(
                with: Data(text.utf8), options: [.fragmentsAllowed]
            )) != nil
            #expect((JSONString(text) != nil) == accepted, "\(text)")
        }
    }

    #if os(macOS) || os(Linux)
    @Test
    func testFailuresTerminateInIsolatedProcesses() throws {
        #if os(macOS)
        let executable = Bundle(for: TestBundleAnchor.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("FailureProbe")
        #else
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("FailureProbe")
        #endif
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        for scenario in ["valid", "literal", "input", "schema"] {
            let process = Process()
            process.executableURL = executable
            process.arguments = [scenario]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            if scenario == "valid" {
                #expect(process.terminationReason == .exit)
                #expect(process.terminationStatus == 0)
            } else {
                #expect(process.terminationReason == .uncaughtSignal, "\(scenario)")
            }
        }
    }
    #endif
}

#if os(macOS)
private final class TestBundleAnchor: NSObject {}
#endif

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
