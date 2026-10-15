public enum AgenticResult: Sendable, Equatable {
    case success(String)
    case failure(AgenticFailure)
}
