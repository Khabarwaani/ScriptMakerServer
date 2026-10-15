/// Provider access that honors cancellation before admission and successful completion.
public protocol AgenticSessionProtocol: AnyObject, Sendable {
    associatedtype Configuration: Sendable
    var configuration: Configuration { get }
    var executionMetadata: [AgenticExecutionMetadata] { get }

    func respond(
        to input: String, instructions: String, for operation: ObjectIdentifier
    ) async -> Result<String, AgenticError>

    func stream(
        to input: String, instructions: String, for operation: ObjectIdentifier,
        yield: @Sendable (String) async throws -> Void
    ) async -> Result<String, AgenticError>

    func pause(_ operation: ObjectIdentifier) async throws(AgenticError)
    func resume(_ operation: ObjectIdentifier) async throws(AgenticError)
}

extension AgenticSessionProtocol {
    public func stream(
        to input: String, instructions: String, for operation: ObjectIdentifier,
        yield: @Sendable (String) async throws -> Void
    ) async -> Result<String, AgenticError> {
        .failure(.unsupported)
    }

    public func pause(_ operation: ObjectIdentifier) async throws(AgenticError) {
        throw .unsupported
    }

    public func resume(_ operation: ObjectIdentifier) async throws(AgenticError) {
        throw .unsupported
    }
}
