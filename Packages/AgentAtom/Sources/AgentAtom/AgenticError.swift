import Foundation

/// An operation or session failure.
public enum AgenticError: Error, Sendable, Equatable {
    case operationFailed(reason: String)
    case generationFailed(reason: String)
    case cancelled
    case busy
    case notRunning
    case unsupported
}

extension AgenticError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .operationFailed(let reason): reason
        case .generationFailed(let reason): reason
        case .cancelled: "The operation was cancelled."
        case .busy: "An operation is already running."
        case .notRunning: "The operation is not running."
        case .unsupported: "The session does not support this action."
        }
    }
}
