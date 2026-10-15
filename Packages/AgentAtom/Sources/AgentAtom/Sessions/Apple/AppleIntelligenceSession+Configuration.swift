@available(macOS 26, iOS 26, visionOS 26, *)
extension AppleIntelligenceSession {
    public struct Configuration: Sendable {
        public let metadata: Set<AgenticExecutionMetadataField>
        @Clamped(0...1, default: 1) private var temperatureValue: Double
        public var temperature: Double { temperatureValue }

        public init(metadata: Set<AgenticExecutionMetadataField> = [], temperature: Double = 1) {
            self.metadata = metadata
            self.temperatureValue = temperature
        }
    }
}

@propertyWrapper
private struct Clamped<Value: BinaryFloatingPoint & Sendable>: Sendable {
    private let range: ClosedRange<Value>
    private let fallback: Value
    private var value: Value

    var wrappedValue: Value {
        get { value }
        set { value = newValue.isNaN ? fallback : min(max(newValue, range.lowerBound), range.upperBound) }
    }

    init(_ range: ClosedRange<Value>, default fallback: Value) {
        self.range = range
        self.fallback = min(max(fallback, range.lowerBound), range.upperBound)
        self.value = self.fallback
    }
}
