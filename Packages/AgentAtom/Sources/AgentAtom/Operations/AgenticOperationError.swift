import Foundation

public enum AgenticOperationError: Error, Sendable, Equatable {
    case modelUnavailable(reason: String)
    case unsupportedStreaming
    case busy
    case cancelled
    case notRunning
    case cannotPause
    case cannotResume
    case contextLengthExceeded
    case refusal
    case incompleteGeneration
    case rateLimited
    case executionFailed
    case invalidInstructions
    case invalidResponse
    case generationFailed(reason: String)
}

extension AgenticOperationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): "Model unavailable: \(reason)"
        case .unsupportedStreaming: "The session does not support streaming."
        case .busy: "An execution is already active."
        case .cancelled: "The execution was cancelled."
        case .notRunning: "The operation has no active execution."
        case .cannotPause: "The session cannot pause generation."
        case .cannotResume: "The session cannot resume generation."
        case .contextLengthExceeded: "The request exceeds the model context limit."
        case .refusal: "The model refused the request."
        case .incompleteGeneration: "The model did not complete the response."
        case .rateLimited: "The model rate limit was reached."
        case .executionFailed: "The model could not complete execution."
        case .invalidInstructions: "The operation could not assemble its instructions."
        case .invalidResponse: "The model returned an unexpected or invalid failure response."
        case .generationFailed(let reason): reason
        }
    }
}
