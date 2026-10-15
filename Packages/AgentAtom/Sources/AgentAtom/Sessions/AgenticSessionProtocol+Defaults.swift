extension AgenticSessionProtocol {
    public func stream(
        to input: String, instructions: String, for operation: ObjectIdentifier,
        yield: @Sendable (String) async throws -> Void
    ) async -> Result<String, AgenticError> {
        .failure(.unsupportedStreaming)
    }

    public func pause(_ operation: ObjectIdentifier) async throws(AgenticError) {
        throw .cannotPause
    }

    public func resume(_ operation: ObjectIdentifier) async throws(AgenticError) {
        throw .cannotResume
    }
}
