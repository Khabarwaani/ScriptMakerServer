import Foundation

extension AgenticSessionProtocol {
    public func stream(
        input: String, instructions: String, operationID: UUID,
        yield: @Sendable (String) async throws -> Void
    ) async -> Result<String, AgenticOperationError> {
        .failure(.unsupportedStreaming)
    }

    public func pause(operationID: UUID) async throws(AgenticOperationError) {
        throw .cannotPause
    }

    public func resume(operationID: UUID) async throws(AgenticOperationError) {
        throw .cannotResume
    }
}
