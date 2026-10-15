extension AgenticSessionProtocol {
    public func stream(_ operation: any AgenticOperationProtocol) async throws -> (
        snapshots: AsyncThrowingStream<String, any Error>, result: Task<AgenticResponse, any Error>
    ) {
        throw AgenticSessionError.unsupportedStreaming
    }
}
