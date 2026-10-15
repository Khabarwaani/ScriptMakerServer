public protocol AgenticSessionProtocol: Sendable {
    func execute(_ operation: any AgenticOperationProtocol) async throws -> AgenticResponse
    func stream(_ operation: any AgenticOperationProtocol) async throws -> AgenticStream
}
