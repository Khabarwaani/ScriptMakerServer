import Foundation

public protocol ModelledSpec<Input, Output>: Spec {
    associatedtype Input: Encodable & Sendable
    associatedtype Output: Decodable & Sendable

    var input: Input { get }
    var output: Output? { get set }
}

/// Default conversion failures terminate execution.
extension ModelledSpec {
    public var inputJSON: JSONString {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(input),
              let text = String(data: data, encoding: .utf8),
              let json = JSONString(text) else {
            preconditionFailure("Failed to encode agent input as JSON")
        }
        return json
    }

    public static var outputSchema: JSONSchema {
        guard let schema = JSONSchema(Output.self) else {
            preconditionFailure("Failed to derive agent output schema")
        }
        return schema
    }
}
