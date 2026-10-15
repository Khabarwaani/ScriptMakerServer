import Foundation

public protocol AgenticSessionProtocol: Sendable {
    associatedtype SessionConfiguration: Sendable
    var configuration: SessionConfiguration { get }
    var executionMetadata: [AgenticExecutionMetadata] { get async }

    func generate(
        input: String, instructions: String, operationID: UUID
    ) async -> Result<String, AgenticError>

    func stream(
        input: String, instructions: String, operationID: UUID,
        yield: @Sendable (String) async throws -> Void
    ) async -> Result<String, AgenticError>

    func pause(operationID: UUID) async throws(AgenticError)
    func resume(operationID: UUID) async throws(AgenticError)
}
