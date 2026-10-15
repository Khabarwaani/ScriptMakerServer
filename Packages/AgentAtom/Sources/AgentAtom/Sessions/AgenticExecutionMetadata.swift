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

    public let operationID: ObjectIdentifier
    public let executionID: UUID
    public let modelIdentifier: String?
    public let duration: Duration?
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(
        operationID: ObjectIdentifier, executionID: UUID,
        modelIdentifier: String? = nil,
        duration: Duration? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil
    ) {
        self.operationID = operationID
        self.executionID = executionID
        self.modelIdentifier = modelIdentifier
        self.duration = duration
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}
