import Foundation

/// An agent specification backed by an encodable input and a decodable output.
///
/// Ordinary synthesized output models receive a default schema. Implement
/// `outputSchema` explicitly when the model uses unsupported custom decoding.
/// Conversion failures in the defaults are programming errors and terminate
/// execution. The failable JSONString/JSONSchema initializers return nil instead.
public protocol ModelledSpec<Input, Output>: Spec {
    associatedtype Input: Encodable & Sendable
    associatedtype Output: Decodable & Sendable

    var input: Input { get }
}

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

    public var outputSchema: JSONSchema {
        guard let schema = JSONSchema(Output.self) else {
            preconditionFailure("Failed to derive agent output schema; provide outputSchema explicitly")
        }
        return schema
    }
}
