import AgentSpec
import Foundation
import XCTest

final class ContractTests: XCTestCase {
    func testModelledSpecDefaultsAndOutputStorage() throws {
        var spec = Example(input: .init(text: "hello", count: 2))
        XCTAssertEqual(Example.identity, Identity(id: "example", name: "Example", version: "1"))
        XCTAssertEqual(Example.role, "Summarise")
        XCTAssertEqual(spec.instructions, "Be concise")
        XCTAssertEqual(spec.inputJSON.rawValue, #"{"count":2,"text":"hello"}"#)
        XCTAssertNil(spec.output)
        spec.output = try JSONDecoder().decode(ExampleOutput.self, from: Data(#"{"result":"done"}"#.utf8))
        XCTAssertEqual(spec.output?.result, "done")
        XCTAssertNotNil(JSONString(Example.outputSchema.rawValue))
        spec.output = nil
        XCTAssertNil(spec.output)
    }

    func testExplicitPropertiesReplaceDefaults() {
        let spec = Overridden()
        XCTAssertEqual(spec.inputJSON.rawValue, "null")
        XCTAssertEqual(Overridden.outputSchema, JSONSchema(String.self))
    }

    func testJSONStringAcceptsAllShapesAndPreservesText() {
        for text in [" {} \n", "[]", #""hello""#, "42", "-1.25e2", "true", "false", "null"] {
            XCTAssertEqual(JSONString(text)?.rawValue, text, text)
        }
        for text in ["", "invalid", "{", "{\"a\":}", "NaN", "true false"] {
            XCTAssertNil(JSONString(text), text)
        }
        let literal: JSONString = #"{"b":2,"a":1}"#
        XCTAssertEqual(literal, JSONString(literal.rawValue))
        XCTAssertEqual(literal.description, literal.debugDescription)
        XCTAssertTrue(literal.description.contains("\n"))
        XCTAssertEqual(JSONString(literal.description)?.description, literal.description)
    }

    func testJSONStringUsesFoundationAcceptanceRules() {
        for text in ["[1,]", #"{"a":1,}"#, "01", "+1"] {
            let accepted = (try? JSONSerialization.jsonObject(
                with: Data(text.utf8), options: [.fragmentsAllowed]
            )) != nil
            XCTAssertEqual(JSONString(text) != nil, accepted, text)
        }
    }

    #if os(macOS) || os(Linux)
    func testFailuresTerminateInIsolatedProcesses() throws {
        #if os(macOS)
        let executable = Bundle(for: ContractTests.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("FailureProbe")
        #else
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("FailureProbe")
        #endif
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        for scenario in ["valid", "literal", "input", "schema"] {
            let process = Process()
            process.executableURL = executable
            process.arguments = [scenario]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            if scenario == "valid" {
                XCTAssertEqual(process.terminationReason, .exit)
                XCTAssertEqual(process.terminationStatus, 0)
            } else {
                XCTAssertEqual(process.terminationReason, .uncaughtSignal, scenario)
            }
        }
    }
    #endif
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
