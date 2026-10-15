import Foundation

public struct AgenticExecutionMetadata: Sendable, Equatable {
    public struct Fields: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let modelIdentifier = Self(rawValue: 1 << 0)
        public static let duration = Self(rawValue: 1 << 1)
        public static let tokenUsage = Self(rawValue: 1 << 2)
    }

    public enum FinishReason: String, Sendable { case stop, lengthExceeded, contentFiltered, other }

    public let operationID: UUID
    public let executionID: UUID
    public let modelIdentifier: String?
    public let modelTier: String?
    public let reasoningEffort: String?
    public let duration: Duration?
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let finishReason: FinishReason?

    public init(
        operationID: UUID, executionID: UUID,
        modelIdentifier: String? = nil, modelTier: String? = nil, reasoningEffort: String? = nil,
        duration: Duration? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil,
        finishReason: FinishReason? = nil
    ) {
        self.operationID = operationID
        self.executionID = executionID
        self.modelIdentifier = modelIdentifier
        self.modelTier = modelTier
        self.reasoningEffort = reasoningEffort
        self.duration = duration
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.finishReason = finishReason
    }
}
