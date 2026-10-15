import Foundation

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

extension AgenticSessionError: LocalizedError, CustomNSError {
    public static var errorDomain: String { "AgentAtom.Session" }

    public var errorCode: Int {
        switch self {
        case .modelUnavailable: 1001
        case .unsupportedStreaming: 1002
        case .busy: 1003
        case .cancelled: 1004
        case .contextLengthExceeded: 1005
        case .refusal: 1006
        case .incompleteGeneration: 1007
        case .rateLimited: 1008
        case .executionFailed: 1009
        case .invalidResponse: 1010
        }
    }

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): "Model unavailable: \(reason)"
        case .unsupportedStreaming: "The session does not support streaming."
        case .busy: "The session already has an active request."
        case .cancelled: "The request was cancelled."
        case .contextLengthExceeded: "The request exceeds the model context limit."
        case .refusal: "The model refused the request."
        case .incompleteGeneration: "The model did not complete the response."
        case .rateLimited: "The model rate limit was reached."
        case .executionFailed: "The model could not complete execution."
        case .invalidResponse: "The model returned an invalid failure response."
        }
    }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: errorDescription ?? "Session execution failed."]
    }
}
