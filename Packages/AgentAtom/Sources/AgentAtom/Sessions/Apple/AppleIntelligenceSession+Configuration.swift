extension AppleIntelligenceSession {
    public struct Configuration: Sendable {
        public let metadata: Set<AgenticMetadataField>
        @ClampedTemperature private var temperatureValue: Double = 1
        public var temperature: Double { temperatureValue }
        public let maximumResponseTokens: Int?

        public init(
            metadata: Set<AgenticMetadataField> = [], temperature: Double = 1,
            maximumResponseTokens: Int? = nil
        ) {
            self.metadata = metadata
            self._temperatureValue = ClampedTemperature(wrappedValue: temperature)
            self.maximumResponseTokens = maximumResponseTokens
        }

        var isValid: Bool {
            if let maximumResponseTokens, maximumResponseTokens <= 0 { return false }
            return true
        }
    }
}
