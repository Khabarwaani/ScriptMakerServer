public protocol AgenticSessionProtocol: Sendable {
    func execute(_ operation: any AgenticOperationProtocol) async throws -> AgenticResponse
    func stream(_ operation: any AgenticOperationProtocol) async throws -> (
        snapshots: AsyncThrowingStream<String, any Error>, result: Task<AgenticResponse, any Error>
    )
}
