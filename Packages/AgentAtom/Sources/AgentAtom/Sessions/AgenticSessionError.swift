import Foundation

public enum AgenticSessionError: Error, Sendable, Equatable, LocalizedError {
    case modelUnavailable(reason: String)
    case invalidConfiguration(reason: String)
    case unsupportedOutput(AgenticOutputKind)
    case unsupportedInput
    case unsupportedStreaming
    case unsupportedSchema(reason: String)
    case unexpectedContent
    case busy
    case cancelled
    case contextLengthExceeded
    case refusal
    case incompleteGeneration
    case rateLimited
    case executionFailed

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): "Model unavailable: \(reason)"
        case .invalidConfiguration(let reason): "Invalid session configuration: \(reason)"
        case .unsupportedOutput(let kind): "The session does not support \(kind.rawValue) output."
        case .unsupportedInput: "The session does not support this input content."
        case .unsupportedStreaming: "The session does not support streaming."
        case .unsupportedSchema(let reason): "Unsupported output schema: \(reason)"
        case .unexpectedContent: "The response content does not match the expected type."
        case .busy: "The session already has an active request."
        case .cancelled: "The request was cancelled."
        case .contextLengthExceeded: "The request exceeds the model context limit."
        case .refusal: "The model refused the request."
        case .incompleteGeneration: "The model did not complete the response."
        case .rateLimited: "The model rate limit was reached."
        case .executionFailed: "The model could not complete execution."
        }
    }
}
