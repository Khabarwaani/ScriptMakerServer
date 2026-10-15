@propertyWrapper
struct ClampedTemperature: Sendable {
    private var value = 1.0

    var wrappedValue: Double {
        get { value }
        set { value = newValue.isNaN ? 1 : min(max(newValue, 0), 1) }
    }

    init(wrappedValue: Double) {
        self.wrappedValue = wrappedValue
    }
}
