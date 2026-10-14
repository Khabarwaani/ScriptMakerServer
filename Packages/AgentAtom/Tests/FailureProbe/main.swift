import AgentAtom
import Foundation

struct FailingInput: Encodable, Sendable {
    func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(0, .init(codingPath: [], debugDescription: "Probe"))
    }
}

struct UnsupportedOutput: Decodable, Sendable {
    init(from decoder: any Decoder) throws {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Probe"))
    }
}

struct Probe: ModelledSpec {
    static let identity = Identity(id: "probe", name: "Probe", version: "1")
    static let role = "Probe"
    let instructions = "Probe"
    let input = FailingInput()
    var output: UnsupportedOutput?
}

switch CommandLine.arguments.last {
case "valid":
    let value: JSONString = "null"
    print(value)
case "literal":
    let value: JSONString = "invalid"
    print(value)
case "input":
    print(Probe().inputJSON)
case "schema":
    print(Probe.outputSchema)
default:
    exit(2)
}
