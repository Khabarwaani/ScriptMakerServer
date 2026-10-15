public struct AgenticFailure: Codable, Sendable, Equatable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}
