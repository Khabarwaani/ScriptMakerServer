public enum AgenticSessionError: Error, Sendable, Equatable {
    case modelUnavailable(reason: String)
    case unsupportedStreaming
    case busy
    case cancelled
    case contextLengthExceeded
    case refusal
    case incompleteGeneration
    case rateLimited
    case executionFailed
    case invalidResponse
}
