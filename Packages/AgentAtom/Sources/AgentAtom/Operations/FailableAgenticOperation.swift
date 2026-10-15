import Foundation

public struct FailableAgenticOperation<Specification: Spec>: AgenticOperationProtocol {
    public let spec: Specification

    public init(spec: Specification) {
        self.spec = spec
    }

    public var inputJSON: JSONString { spec.inputJSON }

    public var outputSchema: JSONSchema {
        get throws { try Specification.outputSchema.allowingFailure() }
    }

    public func makeInstructions() throws -> String {
        assembleOperationInstructions(
            role: Specification.role, spec: spec.instructions, schema: try outputSchema
        )
    }

    public func result(from response: String) throws -> AgenticResult {
        do {
            switch try JSONDecoder().decode(Envelope.self, from: Data(response.utf8)) {
            case .success: return .success(response)
            case .failure(let failure): return .failure(failure)
            }
        } catch {
            throw AgenticSessionError.invalidResponse
        }
    }

    private enum Envelope: Decodable {
        case success
        case failure(NSError)

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            let status = try container.decode(String.self, forKey: Key("status"))
            let keys = Set(container.allKeys.map(\.stringValue))
            switch status {
            case "success" where keys == ["status", "output"]:
                self = .success
            case "failure" where keys == ["status", "failure"]:
                let failure = try container.nestedContainer(keyedBy: Key.self, forKey: Key("failure"))
                guard Set(failure.allKeys.map(\.stringValue)) == ["reason"] else {
                    throw AgenticSessionError.invalidResponse
                }
                self = .failure(
                    NSError(
                        domain: "AgentAtom.Operation", code: 422,
                        userInfo: [NSLocalizedDescriptionKey: try failure.decode(String.self, forKey: Key("reason"))]))
            default:
                throw AgenticSessionError.invalidResponse
            }
        }

        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(_ value: String) { stringValue = value }
            init?(stringValue: String) { self.init(stringValue) }
            init?(intValue: Int) { return nil }
        }
    }
}
