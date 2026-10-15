extension AppleIntelligenceSession {
    public struct Configuration: Sendable {
        public let metadata: Set<AgenticMetadataField>
        public let temperature: Double?
        public let maximumResponseTokens: Int?

        public init(
            metadata: Set<AgenticMetadataField> = [], temperature: Double? = nil,
            maximumResponseTokens: Int? = nil
        ) {
            self.metadata = metadata
            self.temperature = temperature
            self.maximumResponseTokens = maximumResponseTokens
        }

        var isValid: Bool {
            if let temperature, !temperature.isFinite || !(0...2).contains(temperature) { return false }
            if let maximumResponseTokens, maximumResponseTokens <= 0 { return false }
            return true
        }
    }
}
