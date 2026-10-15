extension AgenticSessionProtocol {
    public func stream(_ operation: any AgenticOperationProtocol) async throws -> AgenticStream {
        throw AgenticSessionError.unsupportedStreaming
    }
}
