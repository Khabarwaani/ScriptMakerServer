/// An agent specification backed by an encodable input and a decodable output.
///
/// Ordinary synthesized output models receive a default schema. Implement
/// `outputSchema` explicitly when the model uses unsupported custom decoding.
/// Conversion failures in the defaults are programming errors and terminate
/// execution. Use the throwing JSONString/JSONSchema initializers to recover.
public protocol ModelledSpec<Input, Output>: Spec {
    associatedtype Input: Encodable & Sendable
    associatedtype Output: Decodable & Sendable

    var input: Input { get }
}

extension ModelledSpec {
    public var inputJSON: JSONString {
        do {
            return try JSONString(encoding: input)
        } catch {
            preconditionFailure("Failed to encode agent input as JSON")
        }
    }

    public var outputSchema: JSONSchema {
        do {
            return try JSONSchema(Output.self)
        } catch {
            preconditionFailure("Failed to derive agent output schema; provide outputSchema explicitly")
        }
    }
}
