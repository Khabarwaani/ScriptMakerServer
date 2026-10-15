public enum AgenticMetadataField: Sendable, Hashable, CaseIterable {
    case modelIdentifier, modelTier, reasoningEffort, duration, tokenUsage, finishReason
}

public struct AgenticExecutionMetadata: Sendable, Equatable {
    public enum FinishReason: String, Sendable { case stop, lengthExceeded, contentFiltered, other }

    public let modelIdentifier: String?
    public let modelTier: String?
    public let reasoningEffort: String?
    public let duration: Duration?
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let finishReason: FinishReason?

    public init(
        modelIdentifier: String? = nil, modelTier: String? = nil, reasoningEffort: String? = nil,
        duration: Duration? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil,
        finishReason: FinishReason? = nil
    ) {
        self.modelIdentifier = modelIdentifier
        self.modelTier = modelTier
        self.reasoningEffort = reasoningEffort
        self.duration = duration
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.finishReason = finishReason
    }
}
