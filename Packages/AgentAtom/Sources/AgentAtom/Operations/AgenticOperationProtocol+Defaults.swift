extension AgenticOperationProtocol {
    public func result(from response: String) throws -> AgenticResult {
        .success(response)
    }
}
